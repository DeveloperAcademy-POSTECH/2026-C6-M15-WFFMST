#!/usr/bin/env python3
"""Compare Core ML and GPT wall extraction overlays for the same images."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

from wall_contract import WallExtraction, overlay, rasterize


def fit_panel(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return ImageOps.contain(image.convert("RGB"), size, Image.Resampling.LANCZOS)


def blocked_ratio(mask: Image.Image) -> float:
    histogram = mask.convert("L").histogram()
    return sum(histogram[1:]) / (mask.width * mask.height)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--item", nargs=4, action="append",
        metavar=("IMAGE", "COREML_MASK", "GPT_RESULT", "LABEL"), required=True,
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metrics", type=Path, required=True)
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
    draw.text((16, 14), "Core ML vs GPT-6 Astra · wall extraction", fill="black")
    for column, label in enumerate(("Original", "Core ML overlay", "GPT overlay")):
        draw.text((column * panel_size[0] + 12, 44), label, fill="black")

    metrics = []
    for row, (image_path, coreml_path, gpt_path, label) in enumerate(args.item):
        original = Image.open(image_path).convert("RGB")
        coreml_mask = ImageOps.flip(
            Image.open(coreml_path).convert("L").resize(original.size, Image.Resampling.NEAREST)
        )
        extraction = WallExtraction.load(Path(gpt_path))
        gpt_mask = rasterize(extraction, original.size)
        panels = [original, overlay(original, coreml_mask), overlay(original, gpt_mask)]

        metrics.append({
            "label": label,
            "coreml_blocked_ratio": round(blocked_ratio(coreml_mask), 6),
            "gpt_blocked_ratio": round(blocked_ratio(gpt_mask), 6),
            "gpt_segment_count": len(extraction.segments),
        })
        base_y = header_height + row * (panel_size[1] + row_label_height)
        draw.text((12, base_y + 8), label, fill="black")
        for column, panel in enumerate(panels):
            fitted = fit_panel(panel, (panel_size[0] - 16, panel_size[1] - row_label_height))
            x = column * panel_size[0] + (panel_size[0] - fitted.width) // 2
            y = base_y + row_label_height + (panel_size[1] - row_label_height - fitted.height) // 2
            canvas.paste(fitted, (x, y))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output)
    args.metrics.write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
