from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import torch
from PIL import Image
from safetensors.torch import load_file

from binary_wall_data import letterbox_image
from train_binary_wall import MEAN, STD, _to_tensor, load_base_model, make_binary_model


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare the published baseline and binary fine-tuned model on local plans."
    )
    parser.add_argument("input", type=Path, help="Directory containing floor-plan PNG/JPEG files")
    parser.add_argument("checkpoint", type=Path, help="BinaryWallSegmentation.safetensors path")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("outputs/binary-finetune/actual-comparison.png"),
    )
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument("--tile-size", type=int, default=1024)
    parser.add_argument("--tile-overlap", type=float, default=0.25)
    parser.add_argument("--tile-weight", type=float, default=0.75)
    return parser.parse_args()


def tile_origins(length: int, tile_size: int, overlap: float) -> list[int]:
    if length <= tile_size:
        return [0]
    stride = max(1, round(tile_size * (1 - overlap)))
    count = math.ceil((length - tile_size) / stride) + 1
    return [round(index * (length - tile_size) / (count - 1)) for index in range(count)]


def prepare_tensor(image: Image.Image, device: torch.device) -> torch.Tensor:
    return ((_to_tensor(image) - MEAN) / STD)[None].to(device)


def predict_probability(
    model: torch.nn.Module,
    image: Image.Image,
    device: torch.device,
) -> np.ndarray:
    logits = model(prepare_tensor(image, device))
    return torch.sigmoid(logits)[0, 0].cpu().numpy()


def global_probability(
    model: torch.nn.Module,
    source: Image.Image,
    device: torch.device,
) -> np.ndarray:
    prepared = letterbox_image(source, 512)
    probability = predict_probability(model, prepared, device)
    scale = min(512 / source.width, 512 / source.height)
    resized_width = max(1, round(source.width * scale))
    resized_height = max(1, round(source.height * scale))
    offset_x = (512 - resized_width) // 2
    offset_y = (512 - resized_height) // 2
    content = probability[offset_y : offset_y + resized_height, offset_x : offset_x + resized_width]
    return np.asarray(
        Image.fromarray(content.astype(np.float32), mode="F").resize(
            source.size, Image.Resampling.BILINEAR
        ),
        dtype=np.float32,
    )


def tiled_probability(
    model: torch.nn.Module,
    source: Image.Image,
    device: torch.device,
    tile_size: int,
    overlap: float,
) -> tuple[np.ndarray, int]:
    xs = tile_origins(source.width, tile_size, overlap)
    ys = tile_origins(source.height, tile_size, overlap)
    accumulated = np.zeros((source.height, source.width), dtype=np.float32)
    weights = np.zeros_like(accumulated)
    axis = np.arange(tile_size, dtype=np.float32)
    edge_safe = 0.1 + 0.9 * np.sin(np.pi * (axis + 0.5) / tile_size)
    tile_weight = np.outer(edge_safe, edge_safe)

    for y in ys:
        for x in xs:
            width = min(tile_size, source.width - x)
            height = min(tile_size, source.height - y)
            tile = Image.new("RGB", (tile_size, tile_size), "white")
            tile.paste(source.crop((x, y, x + width, y + height)), (0, 0))
            model_input = tile.resize((512, 512), Image.Resampling.LANCZOS)
            probability = predict_probability(model, model_input, device)
            probability = np.asarray(
                Image.fromarray(probability.astype(np.float32), mode="F").resize(
                    (tile_size, tile_size), Image.Resampling.BILINEAR
                ),
                dtype=np.float32,
            )[:height, :width]
            weight = tile_weight[:height, :width]
            accumulated[y : y + height, x : x + width] += probability * weight
            weights[y : y + height, x : x + width] += weight

    return accumulated / np.maximum(weights, 1e-6), len(xs) * len(ys)


def main() -> None:
    args = parse_args()
    paths = sorted(
        path for path in args.input.iterdir() if path.suffix.lower() in {".png", ".jpg", ".jpeg"}
    )
    if not paths:
        raise ValueError(f"No floor-plan images found in {args.input}")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    published = load_base_model().to(device).eval()
    fine_tuned = make_binary_model(published)
    fine_tuned.load_state_dict(load_file(args.checkpoint), strict=True)
    fine_tuned = fine_tuned.to(device).eval()

    figure, axes = plt.subplots(len(paths), 3, figsize=(15, 5 * len(paths)), squeeze=False)
    results: list[dict[str, object]] = []
    with torch.inference_mode():
        for row, path in enumerate(paths):
            source = Image.open(path).convert("RGB")
            whole_probability = global_probability(fine_tuned, source, device)
            tile_probability, tile_count = tiled_probability(
                fine_tuned,
                source,
                device,
                args.tile_size,
                args.tile_overlap,
            )
            combined_probability = (
                (1 - args.tile_weight) * whole_probability + args.tile_weight * tile_probability
            )
            whole_mask = whole_probability >= args.threshold
            combined_mask = combined_probability >= args.threshold
            results.append(
                {
                    "file": path.name,
                    "tile_count": tile_count,
                    "whole_blocked_ratio": float(whole_mask.mean()),
                    "global_tile_blocked_ratio": float(combined_mask.mean()),
                }
            )

            axes[row, 0].imshow(source)
            axes[row, 1].imshow(~whole_mask, cmap="gray", vmin=0, vmax=1)
            axes[row, 2].imshow(~combined_mask, cmap="gray", vmin=0, vmax=1)
            axes[row, 0].set_ylabel(path.stem, fontsize=10)
            for column in range(3):
                axes[row, column].axis("off")

    axes[0, 0].set_title("Original", fontsize=14)
    axes[0, 1].set_title("Fine-tuned: whole image to 512", fontsize=14)
    axes[0, 2].set_title("Fine-tuned: global + overlap tiles", fontsize=14)
    figure.tight_layout()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(args.output, dpi=160, bbox_inches="tight", facecolor="white")
    plt.close(figure)
    args.output.with_suffix(".json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"device={device}; images={len(paths)}; output={args.output}")


if __name__ == "__main__":
    main()
