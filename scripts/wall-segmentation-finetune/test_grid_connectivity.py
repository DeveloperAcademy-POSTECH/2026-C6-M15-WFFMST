from __future__ import annotations

import unittest

from grid_connectivity import analyze_connectivity, sample_blocked_grid


class GridConnectivityTests(unittest.TestCase):
    def test_opening_connects_both_sides_of_wall(self) -> None:
        blocked = []
        for y in range(5):
            for x in range(5):
                blocked.append(x == 2 and y != 2)

        result = analyze_connectivity(blocked, columns=5, rows=5, significant_minimum=1)

        self.assertEqual(len(result.component_sizes), 1)
        self.assertEqual(result.largest_free_ratio, 1)

    def test_closed_wall_separates_free_space(self) -> None:
        blocked = [x == 2 for _y in range(5) for x in range(5)]

        result = analyze_connectivity(blocked, columns=5, rows=5, significant_minimum=1)

        self.assertEqual(sorted(result.component_sizes), [10, 10])
        self.assertEqual(result.largest_free_ratio, 0.5)
        self.assertEqual(result.disconnected_free_ratio, 0.5)

    def test_probability_grid_samples_two_pixel_cell_centers(self) -> None:
        probability = [0.0] * 16
        probability[1 * 4 + 1] = 0.8
        probability[3 * 4 + 3] = 0.7

        columns, rows, blocked = sample_blocked_grid(
            probability, source_width=4, source_height=4, threshold=0.5, cell_size=2
        )

        self.assertEqual((columns, rows), (2, 2))
        self.assertEqual(blocked, (True, False, False, True))


if __name__ == "__main__":
    unittest.main()
