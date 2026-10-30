from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


PANEL_WIDTH = 560
PANEL_HEIGHT = 420
HEADER_HEIGHT = 54
LABEL_HEIGHT = 70


def fonts() -> tuple[ImageFont.ImageFont, ImageFont.ImageFont]:
    candidates = (
        "/System/Library/Fonts/AppleSDGothicNeo.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    )
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, 24), ImageFont.truetype(candidate, 18)
    return ImageFont.load_default(size=24), ImageFont.load_default(size=18)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("results", type=Path, help="Directory containing metrics.json and generated images")
    parser.add_argument("--output", type=Path, default=None)
    return parser.parse_args()


def fit(image: Image.Image, width: int, height: int, resample: int) -> Image.Image:
    copy = image.copy()
    copy.thumbnail((width, height), resample)
    canvas = Image.new("RGB", (width, height), "white")
    origin = ((width - copy.width) // 2, (height - copy.height) // 2)
    canvas.paste(copy.convert("RGB"), origin)
    return canvas


def mask_panel(mask: Image.Image) -> Image.Image:
    blocked = mask.convert("L").point(lambda value: 0 if value else 255)
    return fit(blocked.convert("RGB"), PANEL_WIDTH, PANEL_HEIGHT, Image.Resampling.NEAREST)


def difference_panel(raw: Image.Image, processed: Image.Image) -> Image.Image:
    raw_values = raw.convert("L")
    processed_values = processed.convert("L")
    if raw_values.size != processed_values.size:
        raise ValueError("raw and processed masks must have the same dimensions")
    raw_pixels = raw_values.load()
    processed_pixels = processed_values.load()
    result = Image.new("RGB", raw_values.size, "white")
    output = result.load()
    for y in range(raw_values.height):
        for x in range(raw_values.width):
            was_blocked = raw_pixels[x, y] > 0
            is_blocked = processed_pixels[x, y] > 0
            if was_blocked and is_blocked:
                output[x, y] = (0, 0, 0)
            elif was_blocked:
                output[x, y] = (240, 64, 64)
            elif is_blocked:
                output[x, y] = (45, 105, 220)
    return fit(result, PANEL_WIDTH, PANEL_HEIGHT, Image.Resampling.NEAREST)


def main() -> None:
    args = parse_args()
    manifest = json.loads((args.results / "metrics.json").read_text(encoding="utf-8"))
    images = manifest["images"]
    output = args.output or args.results / "comparison.png"
    canvas = Image.new(
        "RGB",
        (PANEL_WIDTH * 4, HEADER_HEIGHT + (PANEL_HEIGHT + LABEL_HEIGHT) * len(images)),
        "white",
    )
    draw = ImageDraw.Draw(canvas)
    font, small_font = fonts()
    processed_title = (
        "Cleanup + axis snap"
        if manifest.get("minimumAxisAlignedLengthCells", 0) > 0
        else "Conservative cleanup"
    )
    headers = ("Original", "Core ML raw", processed_title, "Diff")
    for column, title in enumerate(headers):
        draw.text((column * PANEL_WIDTH + 16, 14), title, fill="black", font=font)

    for row, metrics in enumerate(images):
        y = HEADER_HEIGHT + row * (PANEL_HEIGHT + LABEL_HEIGHT)
        original = Image.open(args.results / metrics["normalizedImage"])
        raw = Image.open(args.results / metrics["rawMask"])
        processed = Image.open(args.results / metrics["processedMask"])
        panels = (
            fit(original, PANEL_WIDTH, PANEL_HEIGHT, Image.Resampling.LANCZOS),
            mask_panel(raw),
            mask_panel(processed),
            difference_panel(raw, processed),
        )
        for column, panel in enumerate(panels):
            canvas.paste(panel, (column * PANEL_WIDTH, y))
        label = (
            f"{metrics['fileName']} | removed {metrics['removedCellCount']} "
            f"({metrics['removedComponentCount']} components), added {metrics['addedCellCount']} "
            f"({metrics['filledHoleCount']} holes), straightened {metrics['straightenedBandCount']} bands, "
            f"changed {metrics['changedFraction'] * 100:.3f}%"
        )
        draw.text((16, y + PANEL_HEIGHT + 12), label, fill="black", font=small_font)
        draw.text(
            (PANEL_WIDTH * 3 + 16, y + PANEL_HEIGHT + 12),
            "black: kept / red: removed / blue: added",
            fill="black",
            font=small_font,
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output)
    print(output)


if __name__ == "__main__":
    main()
