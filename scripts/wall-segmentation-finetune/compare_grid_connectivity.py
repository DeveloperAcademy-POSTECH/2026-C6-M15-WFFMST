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
from grid_connectivity import ConnectivityGrid, grid_connectivity
from train_binary_wall import load_base_model, make_binary_model


PALETTE = np.asarray(
    [
        [220, 55, 55],
        [55, 110, 220],
        [35, 170, 95],
        [180, 80, 200],
        [235, 145, 35],
    ],
    dtype=np.uint8,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare 2px obstacle-grid connectivity across probability thresholds."
    )
    parser.add_argument("input", type=Path, help="Directory containing floor-plan images")
    parser.add_argument("checkpoint", type=Path, help="BinaryWallSegmentation.safetensors path")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("outputs/binary-finetune/grid-connectivity.png"),
    )
    parser.add_argument("--thresholds", type=float, nargs="+", default=[0.35, 0.4, 0.5])
    parser.add_argument("--include-token", help="Keep only file names containing this text")
    parser.add_argument("--cell-size", type=int, default=2)
    parser.add_argument("--tile-size", type=int, default=1024)
    parser.add_argument("--tile-overlap", type=float, default=0.25)
    parser.add_argument("--tile-weight", type=float, default=0.75)
    return parser.parse_args()


def connectivity_rgb(grid: ConnectivityGrid) -> np.ndarray:
    result = np.full((grid.rows, grid.columns, 3), 225, dtype=np.uint8)
    labels = np.asarray(grid.labels).reshape(grid.rows, grid.columns)
    blocked = np.asarray(grid.blocked).reshape(grid.rows, grid.columns)
    result[blocked] = 0
    if grid.largest_label >= 0:
        result[labels == grid.largest_label] = 255
    others = sorted(
        (label for label in grid.significant_labels if label != grid.largest_label),
        key=lambda label: grid.component_sizes[label],
        reverse=True,
    )
    for rank, label in enumerate(others):
        result[labels == label] = PALETTE[rank % len(PALETTE)]
    return result


def main() -> None:
    args = parse_args()
    if not args.thresholds or any(not 0 <= threshold <= 1 for threshold in args.thresholds):
        raise ValueError("thresholds must be between 0 and 1")
    paths = sorted(
        path
        for path in args.input.iterdir()
        if path.suffix.lower() in {".png", ".jpg", ".jpeg"}
        and (args.include_token is None or args.include_token in path.name)
    )
    if not paths:
        raise ValueError(f"No matching floor-plan images found in {args.input}")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    base = load_base_model().to(device).eval()
    model = make_binary_model(base)
    model.load_state_dict(load_file(args.checkpoint), strict=True)
    model = model.to(device).eval()

    columns = 1 + len(args.thresholds)
    figure, axes = plt.subplots(
        len(paths), columns, figsize=(5 * columns, 5 * len(paths)), squeeze=False
    )
    results: list[dict[str, object]] = []
    with torch.inference_mode():
        for row, path in enumerate(paths):
            source = Image.open(path).convert("RGB")
            whole = global_probability(model, source, device)
            tiled, tile_count = tiled_probability(
                model, source, device, args.tile_size, args.tile_overlap
            )
            probability = (1 - args.tile_weight) * whole + args.tile_weight * tiled
            axes[row, 0].imshow(source)
            axes[row, 0].set_ylabel(path.stem, fontsize=10)

            item: dict[str, object] = {"file": path.name, "tile_count": tile_count}
            for column, threshold in enumerate(args.thresholds, start=1):
                grid = grid_connectivity(
                    probability.ravel(),
                    source.width,
                    source.height,
                    threshold,
                    args.cell_size,
                )
                axes[row, column].imshow(connectivity_rgb(grid), interpolation="nearest")
                axes[row, column].text(
                    0.5,
                    -0.04,
                    (
                        f"main free {grid.largest_free_ratio:.2%} · "
                        f"separated {grid.disconnected_free_ratio:.3%} · "
                        f"components {len(grid.significant_labels)}"
                    ),
                    transform=axes[row, column].transAxes,
                    ha="center",
                    va="top",
                    fontsize=9,
                )
                item[f"threshold_{threshold:g}"] = {
                    "blocked_ratio": grid.blocked_ratio,
                    "largest_free_ratio": grid.largest_free_ratio,
                    "disconnected_free_ratio": grid.disconnected_free_ratio,
                    "significant_components": len(grid.significant_labels),
                }
            results.append(item)
            for column in range(columns):
                axes[row, column].axis("off")

    axes[0, 0].set_title("Original", fontsize=14)
    for column, threshold in enumerate(args.thresholds, start=1):
        axes[0, column].set_title(f"2px grid · threshold {threshold:g}", fontsize=14)
    figure.suptitle(
        "Black=blocked · white=largest free component · colors=disconnected free components",
        fontsize=12,
    )
    figure.tight_layout(rect=(0, 0, 1, 0.98))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(args.output, dpi=160, bbox_inches="tight", facecolor="white")
    plt.close(figure)
    args.output.with_suffix(".json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"device={device}; images={len(paths)}; output={args.output}")


if __name__ == "__main__":
    main()
