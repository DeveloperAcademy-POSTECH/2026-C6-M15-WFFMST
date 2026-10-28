from __future__ import annotations

import unittest

import torch

from train_binary_wall import binary_loss, soft_cldice_loss


class BinaryWallLossTests(unittest.TestCase):
    def test_cldice_penalizes_a_broken_wall_more_than_a_continuous_wall(self) -> None:
        target = torch.zeros((1, 1, 32, 32))
        target[:, :, 15:18, 3:29] = 1
        continuous = target * 0.98 + 0.01
        broken = continuous.clone()
        broken[:, :, :, 14:18] = 0.01

        self.assertLess(
            soft_cldice_loss(continuous, target).item(),
            soft_cldice_loss(broken, target).item(),
        )

    def test_zero_cldice_weight_preserves_previous_loss(self) -> None:
        logits = torch.zeros((1, 1, 8, 8))
        target = torch.zeros((1, 1, 8, 8))
        self.assertEqual(binary_loss(logits, target).item(), binary_loss(logits, target, 0).item())


if __name__ == "__main__":
    unittest.main()
