from __future__ import annotations

import random
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFont


DOOR_CATEGORY_ID = 3
WALL_CATEGORY_ID = 7
WINDOW_CATEGORY_ID = 8
BLOCKED_CATEGORY_IDS = frozenset({WALL_CATEGORY_ID, WINDOW_CATEGORY_ID})


def _iter_polygons(segmentation: object) -> Iterable[list[float]]:
    if not isinstance(segmentation, Sequence) or isinstance(segmentation, (str, bytes)):
        return
    if segmentation and isinstance(segmentation[0], (int, float)):
        yield [float(value) for value in segmentation]
        return
    for polygon in segmentation:
        if isinstance(polygon, Sequence) and not isinstance(polygon, (str, bytes)):
            yield [float(value) for value in polygon]


def _draw_polygons(
    draw: ImageDraw.ImageDraw,
    segmentations: Sequence[object],
    fill: int,
) -> None:
    for segmentation in segmentations:
        for polygon in _iter_polygons(segmentation):
            if len(polygon) < 6 or len(polygon) % 2:
                continue
            points = [(polygon[index], polygon[index + 1]) for index in range(0, len(polygon), 2)]
            draw.polygon(points, fill=fill)


def build_blocked_mask(
    width: int,
    height: int,
    annotations: dict[str, Sequence[object]],
) -> Image.Image:
    """Builds wall/window=1 and everything else=0, with doors taking precedence."""

    category_ids = annotations.get("category_id", [])
    segmentations = annotations.get("segmentation", [])
    if len(category_ids) != len(segmentations):
        raise ValueError("category_id and segmentation counts do not match")

    blocked: list[object] = []
    doors: list[object] = []
    for category_id, segmentation in zip(category_ids, segmentations, strict=True):
        if int(category_id) in BLOCKED_CATEGORY_IDS:
            blocked.append(segmentation)
        elif int(category_id) == DOOR_CATEGORY_ID:
            doors.append(segmentation)

    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    _draw_polygons(draw, blocked, fill=255)
    # A door is traversable in the app, so it must reopen any overlapping wall polygon.
    _draw_polygons(draw, doors, fill=0)
    return mask


def letterbox_pair(
    image: Image.Image,
    mask: Image.Image,
    size: int,
    fill: int = 255,
) -> tuple[Image.Image, Image.Image]:
    if image.size != mask.size:
        raise ValueError("image and mask sizes must match")
    scale = min(size / image.width, size / image.height)
    resized_size = (
        max(1, round(image.width * scale)),
        max(1, round(image.height * scale)),
    )
    image = image.resize(resized_size, Image.Resampling.LANCZOS)
    mask = mask.resize(resized_size, Image.Resampling.NEAREST)
    canvas = Image.new("RGB", (size, size), (fill, fill, fill))
    mask_canvas = Image.new("L", (size, size), 0)
    origin = ((size - resized_size[0]) // 2, (size - resized_size[1]) // 2)
    canvas.paste(image.convert("RGB"), origin)
    mask_canvas.paste(mask, origin)
    return canvas, mask_canvas


@dataclass(frozen=True)
class SyntheticResult:
    image: Image.Image
    distractor_mask: Image.Image


def _candidate_is_free(candidate: Image.Image, blocked_mask: Image.Image) -> bool:
    candidate_array = np.asarray(candidate, dtype=np.uint8) > 0
    if not candidate_array.any():
        return False
    blocked_array = np.asarray(blocked_mask, dtype=np.uint8) > 0
    overlap = np.logical_and(candidate_array, blocked_array).sum()
    return overlap / candidate_array.sum() <= 0.01


def _paste_candidate(
    image: Image.Image,
    accumulated_mask: Image.Image,
    candidate: Image.Image,
    tone: int,
) -> None:
    ink = Image.new("RGB", image.size, (tone, tone, tone))
    image.paste(ink, mask=candidate)
    accumulated_mask.paste(255, mask=candidate)


def add_free_space_distractors(
    image: Image.Image,
    blocked_mask: Image.Image,
    rng: random.Random,
    attempts: int = 18,
) -> SyntheticResult:
    """Adds text, dimension lines, and furniture-like shapes only to free pixels."""

    image = image.convert("RGB").copy()
    distractor_mask = Image.new("L", image.size, 0)
    font = ImageFont.load_default()
    labels = ("ROOM", "A-101", "3,200", "DN", "UP", "W=1200", "HALL")

    for _ in range(attempts):
        candidate = Image.new("L", image.size, 0)
        draw = ImageDraw.Draw(candidate)
        kind = rng.choice(("text", "dimension", "furniture"))
        x = rng.randint(8, max(8, image.width - 80))
        y = rng.randint(8, max(8, image.height - 45))

        if kind == "text":
            draw.text((x, y), rng.choice(labels), fill=255, font=font, stroke_width=rng.randint(0, 1))
        elif kind == "dimension":
            length = rng.randint(35, 105)
            end = min(image.width - 5, x + length)
            width = rng.randint(1, 2)
            draw.line((x, y, end, y), fill=255, width=width)
            draw.line((x, y - 5, x, y + 5), fill=255, width=width)
            draw.line((end, y - 5, end, y + 5), fill=255, width=width)
        else:
            width = rng.randint(22, 65)
            height = rng.randint(14, 45)
            box = (x, y, min(image.width - 5, x + width), min(image.height - 5, y + height))
            line_width = rng.randint(1, 3)
            if rng.random() < 0.5:
                draw.rectangle(box, outline=255, width=line_width)
                if box[2] - box[0] > 12:
                    mid = (box[0] + box[2]) // 2
                    draw.line((mid, box[1], mid, box[3]), fill=255, width=line_width)
            else:
                draw.ellipse(box, outline=255, width=line_width)

        if _candidate_is_free(candidate, blocked_mask):
            _paste_candidate(image, distractor_mask, candidate, tone=rng.randint(20, 110))

    return SyntheticResult(image=image, distractor_mask=distractor_mask)


def enhance_training_image(image: Image.Image, rng: random.Random) -> Image.Image:
    image = ImageEnhance.Contrast(image).enhance(rng.uniform(0.85, 1.35))
    image = ImageEnhance.Brightness(image).enhance(rng.uniform(0.9, 1.1))
    return image

