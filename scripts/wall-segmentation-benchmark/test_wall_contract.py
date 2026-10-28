import json
import tempfile
import unittest
from pathlib import Path

from wall_contract import WallExtraction, rasterize


class WallContractTests(unittest.TestCase):
    def test_rasterizes_normalized_segment(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.json"
            path.write_text(json.dumps({
                "segments": [{"x1": 0, "y1": 500, "x2": 1000, "y2": 500, "thickness": 10}]
            }))
            mask = rasterize(WallExtraction.load(path), (101, 101))

        self.assertEqual(mask.getpixel((50, 50)), 255)
        self.assertEqual(mask.getpixel((50, 10)), 0)

    def test_rejects_out_of_range_coordinate(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.json"
            path.write_text(json.dumps({
                "segments": [{"x1": -1, "y1": 0, "x2": 1000, "y2": 1000, "thickness": 10}]
            }))
            with self.assertRaises(ValueError):
                WallExtraction.load(path)


if __name__ == "__main__":
    unittest.main()

