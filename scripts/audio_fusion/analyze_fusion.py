#!/usr/bin/env python3
"""Fuse AudioFusionLab exports on a common timeline and calculate metrics.

Only Python's standard library is required. Each input must be one recording
directory exported by the AudioFusionLab iPhone app.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, Sequence


@dataclass(frozen=True)
class Classification:
    time: float
    identifier: str
    confidence: float


@dataclass(frozen=True)
class Marker:
    kind: str
    time: float


@dataclass(frozen=True)
class Recording:
    directory: Path
    session_id: str
    participant_id: str
    device_id: str
    started_at: datetime
    duration: float
    classifications: tuple[Classification, ...]
    markers: tuple[Marker, ...]


@dataclass(frozen=True)
class Alignment:
    device_id: str
    method: str
    scale: float
    offset: float
    anchor_count: int
    residual_mae_seconds: float

    def apply(self, local_time: float) -> float:
        return self.scale * local_time + self.offset


@dataclass(frozen=True)
class DeviceEvent:
    device_id: str
    participant_id: str
    time: float
    confidence: float
    identifiers: tuple[str, ...]


@dataclass(frozen=True)
class FusedEvent:
    time: float
    device_events: tuple[DeviceEvent, ...]

    @property
    def device_count(self) -> int:
        return len(self.device_events)


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def load_recording(directory: Path) -> Recording:
    metadata_path = directory / "metadata.json"
    classifications_path = directory / "classifications.csv"
    markers_path = directory / "manual-markers.csv"
    for required in (metadata_path, classifications_path, markers_path):
        if not required.is_file():
            raise ValueError(f"필수 파일이 없습니다: {required}")

    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    capture = metadata["capture"]
    classifications = tuple(
        Classification(
            time=float(row["recording_time_seconds"]),
            identifier=row["identifier"],
            confidence=float(row["confidence"]),
        )
        for row in _read_csv(classifications_path)
    )
    markers = tuple(
        Marker(kind=row["kind"], time=float(row["recording_time_seconds"]))
        for row in _read_csv(markers_path)
    )
    return Recording(
        directory=directory,
        session_id=str(metadata["sessionID"]),
        participant_id=str(metadata["participantID"]),
        device_id=str(metadata["deviceID"]),
        started_at=datetime.fromisoformat(str(metadata["startedAt"]).replace("Z", "+00:00")),
        duration=float(capture["audioDurationSeconds"]),
        classifications=classifications,
        markers=markers,
    )


def _linear_fit(local: Sequence[float], common: Sequence[float]) -> tuple[float, float, float]:
    if len(local) != len(common) or not local:
        raise ValueError("동기화 기준점 쌍이 올바르지 않습니다.")
    if len(local) == 1:
        scale = 1.0
        offset = common[0] - local[0]
    else:
        local_mean = statistics.fmean(local)
        common_mean = statistics.fmean(common)
        denominator = sum((value - local_mean) ** 2 for value in local)
        if denominator <= 0:
            raise ValueError("서로 다른 시각의 동기화 마커가 두 개 이상 필요합니다.")
        scale = sum(
            (x - local_mean) * (y - common_mean)
            for x, y in zip(local, common)
        ) / denominator
        offset = common_mean - scale * local_mean
    residuals = [abs(scale * x + offset - y) for x, y in zip(local, common)]
    return scale, offset, statistics.fmean(residuals)


def align_recordings(
    recordings: Sequence[Recording],
    reference_device: str | None = None,
) -> tuple[Recording, dict[str, Alignment]]:
    if len(recordings) < 2:
        raise ValueError("융합 분석에는 최소 두 기기의 기록이 필요합니다.")
    session_ids = {recording.session_id for recording in recordings}
    if len(session_ids) != 1:
        raise ValueError(f"sessionID가 서로 다릅니다: {sorted(session_ids)}")
    device_ids = [recording.device_id for recording in recordings]
    if len(device_ids) != len(set(device_ids)):
        raise ValueError("deviceID가 중복됩니다. 기기마다 고유한 이름을 사용하세요.")

    if reference_device is None:
        reference = recordings[0]
    else:
        try:
            reference = next(item for item in recordings if item.device_id == reference_device)
        except StopIteration as error:
            raise ValueError(f"기준 기기를 찾을 수 없습니다: {reference_device}") from error

    reference_sync = sorted(marker.time for marker in reference.markers if marker.kind == "sync")
    alignments: dict[str, Alignment] = {}
    for recording in recordings:
        local_sync = sorted(marker.time for marker in recording.markers if marker.kind == "sync")
        pair_count = min(len(reference_sync), len(local_sync))
        if pair_count == 0:
            raise ValueError(
                f"{recording.device_id} 또는 기준 기기에 sync 마커가 없습니다. "
                "모든 기기에서 같은 시작 동기화음을 듣고 마커를 남기세요."
            )
        if recording.device_id == reference.device_id:
            scale, offset, residual = 1.0, 0.0, 0.0
            method = "reference"
        else:
            scale, offset, residual = _linear_fit(
                local_sync[:pair_count], reference_sync[:pair_count]
            )
            method = "sync_affine" if pair_count >= 2 else "sync_offset"
        alignments[recording.device_id] = Alignment(
            device_id=recording.device_id,
            method=method,
            scale=scale,
            offset=offset,
            anchor_count=pair_count,
            residual_mae_seconds=residual,
        )
    return reference, alignments


def _matches_identifier(identifier: str, patterns: Sequence[str]) -> bool:
    lowered = identifier.casefold()
    return any(pattern.casefold() in lowered for pattern in patterns)


def device_events(
    recording: Recording,
    alignment: Alignment,
    label_patterns: Sequence[str],
    confidence_threshold: float,
    merge_gap: float,
) -> list[DeviceEvent]:
    candidates = sorted(
        (
            Classification(
                time=alignment.apply(item.time),
                identifier=item.identifier,
                confidence=item.confidence,
            )
            for item in recording.classifications
            if item.confidence >= confidence_threshold
            and _matches_identifier(item.identifier, label_patterns)
        ),
        key=lambda item: item.time,
    )
    groups: list[list[Classification]] = []
    for candidate in candidates:
        if not groups or candidate.time - groups[-1][-1].time > merge_gap:
            groups.append([candidate])
        else:
            groups[-1].append(candidate)

    events: list[DeviceEvent] = []
    for group in groups:
        strongest = max(group, key=lambda item: item.confidence)
        events.append(DeviceEvent(
            device_id=recording.device_id,
            participant_id=recording.participant_id,
            time=strongest.time,
            confidence=strongest.confidence,
            identifiers=tuple(sorted({item.identifier for item in group})),
        ))
    return events


def fuse_events(events: Iterable[DeviceEvent], tolerance: float) -> list[FusedEvent]:
    clusters: list[list[DeviceEvent]] = []
    for event in sorted(events, key=lambda item: item.time):
        if not clusters:
            clusters.append([event])
            continue
        center = statistics.median(item.time for item in clusters[-1])
        if abs(event.time - center) <= tolerance:
            clusters[-1].append(event)
        else:
            clusters.append([event])

    fused: list[FusedEvent] = []
    for cluster in clusters:
        strongest_by_device: dict[str, DeviceEvent] = {}
        for event in cluster:
            previous = strongest_by_device.get(event.device_id)
            if previous is None or event.confidence > previous.confidence:
                strongest_by_device[event.device_id] = event
        selected = tuple(sorted(strongest_by_device.values(), key=lambda item: item.device_id))
        fused.append(FusedEvent(
            time=statistics.median(item.time for item in selected),
            device_events=selected,
        ))
    return fused


def _percentile(values: Sequence[float], quantile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = (len(ordered) - 1) * quantile
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return ordered[lower]
    fraction = index - lower
    return ordered[lower] * (1 - fraction) + ordered[upper] * fraction


def evaluate(
    detections: Sequence[float],
    ground_truth: Sequence[float],
    match_tolerance: float,
    duration_minutes: float,
) -> dict[str, float | int | None]:
    available_detections = set(range(len(detections)))
    available_truth = set(range(len(ground_truth)))
    pairs = sorted(
        (
            (abs(detection - truth), detection - truth, detection_index, truth_index)
            for detection_index, detection in enumerate(detections)
            for truth_index, truth in enumerate(ground_truth)
            if abs(detection - truth) <= match_tolerance
        ),
        key=lambda item: item[0],
    )
    errors: list[float] = []
    for _, signed_error, detection_index, truth_index in pairs:
        if detection_index not in available_detections or truth_index not in available_truth:
            continue
        available_detections.remove(detection_index)
        available_truth.remove(truth_index)
        errors.append(signed_error)

    true_positive = len(errors)
    false_positive = len(detections) - true_positive
    false_negative = len(ground_truth) - true_positive
    precision = true_positive / len(detections) if detections else 0.0
    recall = true_positive / len(ground_truth) if ground_truth else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    absolute_errors = [abs(value) for value in errors]
    return {
        "ground_truth_count": len(ground_truth),
        "detection_count": len(detections),
        "true_positive": true_positive,
        "false_positive": false_positive,
        "false_negative": false_negative,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "false_positives_per_minute": false_positive / duration_minutes if duration_minutes > 0 else None,
        "timestamp_bias_seconds": statistics.fmean(errors) if errors else None,
        "timestamp_mae_seconds": statistics.fmean(absolute_errors) if absolute_errors else None,
        "timestamp_p95_seconds": _percentile(absolute_errors, 0.95),
    }


def _write_csv(path: Path, headers: Sequence[str], rows: Iterable[Sequence[object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(headers)
        writer.writerows(rows)


def run_analysis(args: argparse.Namespace) -> dict[str, object]:
    recordings = [load_recording(Path(path).resolve()) for path in args.recording]
    reference, alignments = align_recordings(recordings, args.reference_device)
    patterns = tuple(item.strip() for item in args.labels.split(",") if item.strip())
    if not patterns:
        raise ValueError("최소 한 개의 label pattern이 필요합니다.")

    per_device: list[DeviceEvent] = []
    for recording in recordings:
        per_device.extend(device_events(
            recording=recording,
            alignment=alignments[recording.device_id],
            label_patterns=patterns,
            confidence_threshold=args.confidence,
            merge_gap=args.device_merge_gap,
        ))
    fused = fuse_events(per_device, args.fusion_tolerance)

    truth_source = reference
    if args.ground_truth_device:
        try:
            truth_source = next(
                item for item in recordings if item.device_id == args.ground_truth_device
            )
        except StopIteration as error:
            raise ValueError(
                f"정답 마커 기기를 찾을 수 없습니다: {args.ground_truth_device}"
            ) from error
    truth_alignment = alignments[truth_source.device_id]
    ground_truth = sorted(
        truth_alignment.apply(marker.time)
        for marker in truth_source.markers
        if marker.kind == "shotCandidate"
    )
    if not ground_truth:
        raise ValueError(
            f"{truth_source.device_id}에 shotCandidate 마커가 없습니다. "
            "정답 마커가 있는 기기를 --ground-truth-device로 지정하세요."
        )

    thresholds = args.min_devices or list(range(1, len(recordings) + 1))
    invalid = [value for value in thresholds if value < 1 or value > len(recordings)]
    if invalid:
        raise ValueError(f"min-devices 범위는 1~{len(recordings)}입니다: {invalid}")
    evaluations: list[dict[str, object]] = []
    for minimum in sorted(set(thresholds)):
        detection_times = [event.time for event in fused if event.device_count >= minimum]
        metrics = evaluate(
            detection_times,
            ground_truth,
            args.match_tolerance,
            reference.duration / 60,
        )
        evaluations.append({"minimum_device_count": minimum, **metrics})

    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    _write_csv(
        output / "alignment.csv",
        ("device_id", "method", "scale", "offset_seconds", "anchor_count", "residual_mae_seconds"),
        (
            (
                item.device_id,
                item.method,
                f"{item.scale:.12f}",
                f"{item.offset:.9f}",
                item.anchor_count,
                f"{item.residual_mae_seconds:.9f}",
            )
            for item in alignments.values()
        ),
    )
    _write_csv(
        output / "device-events.csv",
        ("device_id", "participant_id", "common_time_seconds", "confidence", "identifiers"),
        (
            (
                event.device_id,
                event.participant_id,
                f"{event.time:.9f}",
                f"{event.confidence:.9f}",
                "|".join(event.identifiers),
            )
            for event in sorted(per_device, key=lambda item: item.time)
        ),
    )
    _write_csv(
        output / "fused-events.csv",
        ("common_time_seconds", "device_count", "device_ids", "max_confidence"),
        (
            (
                f"{event.time:.9f}",
                event.device_count,
                "|".join(item.device_id for item in event.device_events),
                f"{max(item.confidence for item in event.device_events):.9f}",
            )
            for event in fused
        ),
    )
    metric_headers = tuple(evaluations[0].keys())
    _write_csv(
        output / "metrics.csv",
        metric_headers,
        ([row[key] for key in metric_headers] for row in evaluations),
    )

    report: dict[str, object] = {
        "session_id": reference.session_id,
        "reference_device": reference.device_id,
        "ground_truth_device": truth_source.device_id,
        "recording_count": len(recordings),
        "labels": list(patterns),
        "confidence_threshold": args.confidence,
        "device_merge_gap_seconds": args.device_merge_gap,
        "fusion_tolerance_seconds": args.fusion_tolerance,
        "match_tolerance_seconds": args.match_tolerance,
        "ground_truth_count": len(ground_truth),
        "evaluations": evaluations,
    }
    (output / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return report


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--recording",
        action="append",
        required=True,
        help="AudioFusionLab recording directory. Repeat once per device.",
    )
    parser.add_argument("--output", required=True, help="Directory for analysis CSV/JSON files.")
    parser.add_argument("--reference-device", help="deviceID used as the common timeline.")
    parser.add_argument("--ground-truth-device", help="deviceID whose shotCandidate markers are truth.")
    parser.add_argument("--labels", default="gunshot,gunfire", help="Comma-separated identifier substrings.")
    parser.add_argument("--confidence", type=float, default=0.1)
    parser.add_argument("--device-merge-gap", type=float, default=0.45)
    parser.add_argument("--fusion-tolerance", type=float, default=0.5)
    parser.add_argument("--match-tolerance", type=float, default=1.0)
    parser.add_argument("--min-devices", type=int, action="append")
    return parser.parse_args(argv)


def main() -> int:
    try:
        report = run_analysis(parse_args())
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}")
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
