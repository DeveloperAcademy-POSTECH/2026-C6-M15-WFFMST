import argparse
import csv
import json
import tempfile
import unittest
from pathlib import Path

from scripts.audio_fusion.analyze_fusion import run_analysis


class AnalyzeFusionTests(unittest.TestCase):
    def make_recording(
        self,
        root: Path,
        device_id: str,
        sync: list[float],
        shots: list[float],
        detections: list[tuple[float, float]],
    ) -> Path:
        directory = root / device_id
        directory.mkdir()
        metadata = {
            "sessionID": "session-1",
            "participantID": f"operator-{device_id}",
            "deviceID": device_id,
            "startedAt": "2026-10-26T00:00:00Z",
            "capture": {"audioDurationSeconds": 60.0},
        }
        (directory / "metadata.json").write_text(json.dumps(metadata), encoding="utf-8")
        with (directory / "classifications.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow([
                "window_index", "rank", "window_start_seconds", "recording_time_seconds",
                "duration_seconds", "identifier", "confidence",
            ])
            for index, (time, confidence) in enumerate(detections):
                writer.writerow([index, 1, time, time, 0.975, "gunshot_or_gunfire", confidence])
        with (directory / "manual-markers.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["id", "kind", "recording_time_seconds", "wall_clock"])
            for index, time in enumerate(sync):
                writer.writerow([f"sync-{index}", "sync", time, "2026-10-26T00:00:00Z"])
            for index, time in enumerate(shots):
                writer.writerow([f"shot-{index}", "shotCandidate", time, "2026-10-26T00:00:00Z"])
        return directory

    def test_affine_alignment_and_consensus_metrics(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = self.make_recording(
                root, "A", [2.0, 52.0], [10.0, 20.0],
                [(9.9, 0.8), (10.1, 0.7), (20.2, 0.9), (40.0, 0.5)],
            )
            # Device B clock is shifted +1 s and runs 2% faster.
            second = self.make_recording(
                root, "B", [3.04, 54.04], [],
                [(11.10, 0.75), (21.36, 0.85)],
            )
            output = root / "output"
            args = argparse.Namespace(
                recording=[str(first), str(second)],
                output=str(output),
                reference_device="A",
                ground_truth_device="A",
                labels="gunshot,gunfire",
                confidence=0.1,
                device_merge_gap=0.45,
                fusion_tolerance=0.5,
                match_tolerance=1.0,
                min_devices=[1, 2],
            )

            report = run_analysis(args)

            self.assertEqual(report["ground_truth_count"], 2)
            one_device, two_devices = report["evaluations"]
            self.assertEqual(one_device["true_positive"], 2)
            self.assertEqual(one_device["false_positive"], 1)
            self.assertEqual(two_devices["true_positive"], 2)
            self.assertEqual(two_devices["false_positive"], 0)
            self.assertAlmostEqual(two_devices["recall"], 1.0)
            self.assertTrue((output / "alignment.csv").is_file())
            self.assertTrue((output / "fused-events.csv").is_file())
            self.assertTrue((output / "metrics.csv").is_file())


if __name__ == "__main__":
    unittest.main()
