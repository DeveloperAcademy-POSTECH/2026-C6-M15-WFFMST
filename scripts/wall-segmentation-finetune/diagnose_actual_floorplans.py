from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import torch
from PIL import Image
from safetensors.torch import load_file

from compare_actual_floorplans import global_probability, tiled_probability
from train_binary_wall import load_base_model, make_binary_model


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Visualize probability and uncertainty for the binary wall model."
    )
    parser.add_argument("input", type=Path, help="Directory containing floor-plan PNG/JPEG files")
    parser.add_argument("checkpoint", type=Path, help="BinaryWallSegmentation.safetensors path")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("outputs/binary-finetune/actual-diagnostics.png"),
    )
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument("--uncertainty-margin", type=float, default=0.15)
    parser.add_argument("--tile-size", type=int, default=1024)
    parser.add_argument("--tile-overlap", type=float, default=0.25)
    parser.add_argument("--tile-weight", type=float, default=0.75)
    return parser.parse_args()


def uncertainty_mask(probability: np.ndarray, threshold: float, margin: float) -> np.ndarray:
    if not 0 <= threshold <= 1:
        raise ValueError("threshold must be between 0 and 1")
    if not 0 <= margin <= 0.5:
        raise ValueError("uncertainty-margin must be between 0 and 0.5")
    return np.abs(probability - threshold) <= margin + np.finfo(np.float32).eps


def diagnostic_overlay(
    source: Image.Image,
    probability: np.ndarray,
    threshold: float,
    margin: float,
) -> np.ndarray:
    image = np.asarray(source.convert("RGB"), dtype=np.float32) / 255
    blocked = probability >= threshold
    uncertain = uncertainty_mask(probability, threshold, margin)

    overlay = image.copy()
    overlay[blocked] = 0.55 * overlay[blocked] + 0.45 * np.array([1.0, 0.1, 0.1])
    overlay[uncertain] = 0.35 * image[uncertain] + 0.65 * np.array([1.0, 0.75, 0.0])
    return np.clip(overlay, 0, 1)


def main() -> None:
    args = parse_args()
    paths = sorted(
        path for path in args.input.iterdir() if path.suffix.lower() in {".png", ".jpg", ".jpeg"}
    )
    if not paths:
        raise ValueError(f"No floor-plan images found in {args.input}")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    base = load_base_model().to(device).eval()
    model = make_binary_model(base)
    model.load_state_dict(load_file(args.checkpoint), strict=True)
    model = model.to(device).eval()

    figure, axes = plt.subplots(len(paths), 4, figsize=(20, 5 * len(paths)), squeeze=False)
    results: list[dict[str, object]] = []
    with torch.inference_mode():
        for row, path in enumerate(paths):
            source = Image.open(path).convert("RGB")
            whole = global_probability(model, source, device)
            tiled, tile_count = tiled_probability(
                model, source, device, args.tile_size, args.tile_overlap
            )
            probability = (1 - args.tile_weight) * whole + args.tile_weight * tiled
            blocked = probability >= args.threshold
            uncertain = uncertainty_mask(
                probability, args.threshold, args.uncertainty_margin
            )
            results.append(
                {
                    "file": path.name,
                    "tile_count": tile_count,
                    "blocked_ratio": float(blocked.mean()),
                    "uncertain_ratio": float(uncertain.mean()),
                    "mean_probability": float(probability.mean()),
                }
            )

            axes[row, 0].imshow(source)
            heatmap = axes[row, 1].imshow(probability, cmap="magma", vmin=0, vmax=1)
            axes[row, 2].imshow(~blocked, cmap="gray", vmin=0, vmax=1)
            axes[row, 3].imshow(
                diagnostic_overlay(
                    source, probability, args.threshold, args.uncertainty_margin
                )
            )
            axes[row, 0].set_ylabel(path.stem, fontsize=10)
            for column in range(4):
                axes[row, column].axis("off")

    axes[0, 0].set_title("Original", fontsize=14)
    axes[0, 1].set_title("Blocked probability (0–1)", fontsize=14)
    axes[0, 2].set_title(f"Binary mask (threshold {args.threshold:g})", fontsize=14)
    axes[0, 3].set_title(
        f"Diagnostic overlay (red=blocked, amber=±{args.uncertainty_margin:g})",
        fontsize=14,
    )
    figure.colorbar(heatmap, ax=axes[:, 1], fraction=0.015, pad=0.01)
    figure.tight_layout(rect=(0, 0, 0.98, 1))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(args.output, dpi=160, bbox_inches="tight", facecolor="white")
    plt.close(figure)
    args.output.with_suffix(".json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"device={device}; images={len(paths)}; output={args.output}")


if __name__ == "__main__":
    main()
