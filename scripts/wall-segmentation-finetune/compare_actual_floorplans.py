from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib.pyplot as plt
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
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    paths = sorted(
        path for path in args.input.iterdir() if path.suffix.lower() in {".png", ".jpg", ".jpeg"}
    )
    if not paths:
        raise ValueError(f"No floor-plan images found in {args.input}")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    baseline = load_base_model().to(device).eval()
    fine_tuned = make_binary_model(baseline)
    fine_tuned.load_state_dict(load_file(args.checkpoint), strict=True)
    fine_tuned = fine_tuned.to(device).eval()

    figure, axes = plt.subplots(len(paths), 3, figsize=(15, 5 * len(paths)), squeeze=False)
    results: list[dict[str, object]] = []
    with torch.inference_mode():
        for row, path in enumerate(paths):
            prepared = letterbox_image(Image.open(path).convert("RGB"), 512)
            image = ((_to_tensor(prepared) - MEAN) / STD)[None].to(device)
            baseline_probability = torch.softmax(baseline(image), dim=1)[0]
            baseline_mask = (
                baseline_probability[1] + baseline_probability[3] >= args.threshold
            ).cpu().numpy()
            fine_tuned_mask = (
                torch.sigmoid(fine_tuned(image))[0, 0] >= args.threshold
            ).cpu().numpy()
            results.append(
                {
                    "file": path.name,
                    "baseline_blocked_ratio": float(baseline_mask.mean()),
                    "fine_tuned_blocked_ratio": float(fine_tuned_mask.mean()),
                }
            )

            axes[row, 0].imshow(prepared)
            axes[row, 1].imshow(~baseline_mask, cmap="gray", vmin=0, vmax=1)
            axes[row, 2].imshow(~fine_tuned_mask, cmap="gray", vmin=0, vmax=1)
            axes[row, 0].set_ylabel(path.stem, fontsize=10)
            for column in range(3):
                axes[row, column].axis("off")

    axes[0, 0].set_title("Original (512 letterbox)", fontsize=14)
    axes[0, 1].set_title("Baseline blocked (wall + window)", fontsize=14)
    axes[0, 2].set_title("Fine-tuned blocked", fontsize=14)
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
