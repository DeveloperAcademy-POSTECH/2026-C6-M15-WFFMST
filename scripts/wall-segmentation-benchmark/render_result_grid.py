#!/usr/bin/env python3
"""Render several vector wall extraction results as one three-column grid."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

from wall_contract import WallExtraction, overlay, rasterize


def fit_panel(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return ImageOps.contain(image.convert("RGB"), size, Image.Resampling.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--item", nargs=3, action="append", metavar=("IMAGE", "RESULT", "LABEL"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--title", default="Wall extraction comparison")
    args = parser.parse_args()

    panel_size = (500, 390)
    header_height = 72
    row_label_height = 34
    canvas = Image.new(
        "RGB",
        (panel_size[0] * 3, header_height + (panel_size[1] + row_label_height) * len(args.item)),
        "white",
    )
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 14), args.title, fill="black")
    for column, label in enumerate(("Original", "Wall overlay", "Blocked mask")):
        draw.text((column * panel_size[0] + 12, 44), label, fill="black")

    for row, (image_path, result_path, label) in enumerate(args.item):
        original = Image.open(image_path).convert("RGB")
        extraction = WallExtraction.load(Path(result_path))
        mask = rasterize(extraction, original.size)
        panels = [original, overlay(original, mask), Image.merge("RGB", (mask, mask, mask))]
        base_y = header_height + row * (panel_size[1] + row_label_height)
        draw.text((12, base_y + 8), label, fill="black")
        for column, panel in enumerate(panels):
            fitted = fit_panel(panel, (panel_size[0] - 16, panel_size[1] - row_label_height))
            x = column * panel_size[0] + (panel_size[0] - fitted.width) // 2
            y = base_y + row_label_height + (panel_size[1] - row_label_height - fitted.height) // 2
            canvas.paste(fitted, (x, y))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output)


if __name__ == "__main__":
    main()
