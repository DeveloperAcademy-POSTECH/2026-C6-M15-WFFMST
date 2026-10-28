#!/usr/bin/env python3
"""Render an original, vector overlay, and blocked mask into one comparison image."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

from wall_contract import WallExtraction, overlay, rasterize


def fit_panel(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return ImageOps.contain(image.convert("RGB"), size, Image.Resampling.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("result", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--title", default="Generative wall extraction")
    args = parser.parse_args()

    original = Image.open(args.image).convert("RGB")
    extraction = WallExtraction.load(args.result)
    mask = rasterize(extraction, original.size)
    panels = [original, overlay(original, mask), Image.merge("RGB", (mask, mask, mask))]
    labels = ["Original", "Wall overlay", "Blocked mask"]

    panel_size = (520, 420)
    label_height = 44
    canvas = Image.new("RGB", (panel_size[0] * 3, panel_size[1] + label_height + 52), "white")
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 14), args.title, fill="black")
    for index, (panel, label) in enumerate(zip(panels, labels)):
        fitted = fit_panel(panel, panel_size)
        x = index * panel_size[0] + (panel_size[0] - fitted.width) // 2
        y = 52 + (panel_size[1] - fitted.height) // 2
        canvas.paste(fitted, (x, y))
        draw.text((index * panel_size[0] + 12, 52 + panel_size[1] + 12), label, fill="black")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output)


if __name__ == "__main__":
    main()

