from __future__ import annotations

import random
import unittest

import numpy as np
from PIL import Image

from binary_wall_data import (
    add_free_space_distractors,
    build_blocked_mask,
    build_letterboxed_blocked_mask,
    letterbox_pair,
)


class BinaryWallDataTests(unittest.TestCase):
    def test_wall_and_window_are_blocked_but_door_reopens_overlap(self) -> None:
        annotations = {
            "category_id": [7, 8, 3, 5],
            "segmentation": [
                [[1, 1, 18, 1, 18, 5, 1, 5]],
                [[1, 10, 18, 10, 18, 14, 1, 14]],
                [[8, 1, 12, 1, 12, 5, 8, 5]],
                [[3, 6, 16, 6, 16, 9, 3, 9]],
            ],
        }
        mask = np.asarray(build_blocked_mask(20, 16, annotations))
        self.assertEqual(mask[3, 3], 255)
        self.assertEqual(mask[12, 3], 255)
        self.assertEqual(mask[3, 10], 0)
        self.assertEqual(mask[7, 5], 0)

    def test_letterbox_preserves_binary_mask_values(self) -> None:
        image = Image.new("RGB", (20, 10), "white")
        mask = Image.new("L", (20, 10), 0)
        mask.paste(255, (2, 2, 8, 8))
        resized_image, resized_mask = letterbox_pair(image, mask, 32)
        self.assertEqual(resized_image.size, (32, 32))
        self.assertEqual(set(np.unique(np.asarray(resized_mask))), {0, 255})

    def test_direct_letterbox_rasterization_preserves_door_precedence(self) -> None:
        annotations = {
            "category_id": [7, 3],
            "segmentation": [
                [[0, 0, 1000, 0, 1000, 200, 0, 200]],
                [[400, 0, 600, 0, 600, 200, 400, 200]],
            ],
        }
        mask = np.asarray(build_letterboxed_blocked_mask(1000, 500, annotations, 100))
        self.assertEqual(mask[30, 10], 255)
        self.assertEqual(mask[30, 50], 0)

    def test_synthetic_distractors_do_not_overlap_blocked_pixels(self) -> None:
        image = Image.new("RGB", (128, 128), "white")
        mask = Image.new("L", (128, 128), 0)
        mask.paste(255, (0, 0, 128, 32))
        result = add_free_space_distractors(image, mask, random.Random(7), attempts=60)
        distractor = np.asarray(result.distractor_mask) > 0
        blocked = np.asarray(mask) > 0
        self.assertTrue(distractor.any())
        self.assertFalse(np.logical_and(distractor, blocked).any())


if __name__ == "__main__":
    unittest.main()

