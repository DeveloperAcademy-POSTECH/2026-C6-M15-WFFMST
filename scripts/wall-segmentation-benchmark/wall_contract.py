"""Shared vector contract and rasterizer for generative wall extraction spikes."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


COORDINATE_MAX = 1000


@dataclass(frozen=True)
class WallSegment:
    x1: int
    y1: int
    x2: int
    y2: int
    thickness: int

    @classmethod
    def from_dict(cls, value: dict[str, Any]) -> "WallSegment":
        segment = cls(**{key: int(value[key]) for key in cls.__annotations__})
        for coordinate in (segment.x1, segment.y1, segment.x2, segment.y2):
            if not 0 <= coordinate <= COORDINATE_MAX:
                raise ValueError(f"coordinate is outside 0...{COORDINATE_MAX}: {coordinate}")
        if not 1 <= segment.thickness <= 200:
            raise ValueError(f"thickness is outside 1...200: {segment.thickness}")
        return segment


@dataclass(frozen=True)
class WallExtraction:
    segments: tuple[WallSegment, ...]

    @classmethod
    def load(cls, path: Path) -> "WallExtraction":
        payload = json.loads(path.read_text(encoding="utf-8"))
        raw_segments = payload.get("segments")
        if not isinstance(raw_segments, list):
            raise ValueError("segments must be an array")
        if len(raw_segments) > 256:
            raise ValueError("segments must contain at most 256 items")
        return cls(tuple(WallSegment.from_dict(value) for value in raw_segments))


def rasterize(extraction: WallExtraction, size: tuple[int, int]) -> Image.Image:
    """Rasterize normalized centerlines to an 8-bit blocked mask."""
    width, height = size
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    scale_x = max(width - 1, 1) / COORDINATE_MAX
    scale_y = max(height - 1, 1) / COORDINATE_MAX
    thickness_scale = (scale_x + scale_y) / 2

    for segment in extraction.segments:
        draw.line(
            (
                round(segment.x1 * scale_x),
                round(segment.y1 * scale_y),
                round(segment.x2 * scale_x),
                round(segment.y2 * scale_y),
            ),
            fill=255,
            width=max(1, round(segment.thickness * thickness_scale)),
        )
    return mask


def overlay(image: Image.Image, mask: Image.Image) -> Image.Image:
    base = image.convert("RGBA")
    blocked = Image.new("RGBA", base.size, (255, 59, 48, 0))
    blocked.putalpha(mask.point(lambda value: 150 if value else 0))
    return Image.alpha_composite(base, blocked).convert("RGB")

