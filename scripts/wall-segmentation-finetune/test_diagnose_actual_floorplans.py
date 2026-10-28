import unittest

import numpy as np
from PIL import Image

from diagnose_actual_floorplans import diagnostic_overlay, uncertainty_mask


class DiagnoseActualFloorplansTests(unittest.TestCase):
    def test_uncertainty_mask_includes_probability_near_threshold(self) -> None:
        probability = np.array([[0.2, 0.35, 0.5, 0.65, 0.8]], dtype=np.float32)

        result = uncertainty_mask(probability, threshold=0.5, margin=0.15)

        np.testing.assert_array_equal(result, [[False, True, True, True, False]])

    def test_overlay_marks_blocked_red_and_uncertain_amber(self) -> None:
        source = Image.new("RGB", (2, 1), "white")
        probability = np.array([[0.9, 0.5]], dtype=np.float32)

        result = diagnostic_overlay(source, probability, threshold=0.5, margin=0.15)

        self.assertGreater(result[0, 0, 0], result[0, 0, 1])
        self.assertGreater(result[0, 1, 0], result[0, 1, 2])
        self.assertGreater(result[0, 1, 1], result[0, 1, 2])

    def test_invalid_margin_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            uncertainty_mask(np.zeros((1, 1)), threshold=0.5, margin=0.6)


if __name__ == "__main__":
    unittest.main()
