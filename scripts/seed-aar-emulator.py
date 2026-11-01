#!/usr/bin/env python3
"""Firebase 에뮬레이터에 AAR 시험용 세션·대원·기록과 보정 결과(result.json)를 넣는다.

에뮬레이터 관리자 권한(Bearer owner)으로 보안 규칙을 거치지 않고 바로 쓴다. 운영 Firebase에는 쓰지 않는다.

    firebase emulators:start            # 다른 터미널에서 먼저 켠다
    python3 scripts/seed-aar-emulator.py --instructor-uid <교관 앱 uid>

교관 앱이 세션을 읽으려면 `--instructor-uid`에 교관 앱의 익명 로그인 uid를 넣는다.
uid는 교관 앱을 (Emulator) 스킴으로 실행한 뒤 http://localhost:4000/auth 에서 확인한다.
출력된 sessionID를 교관 앱 스킴 환경 변수 `CQB_AAR_SESSION_ID`에 넣으면 앱이 그 세션의 AAR을 바로 연다.

`--floor-plan-id`를 주지 않으면 시험용 도면(격자 그림, 장애물 격자, navigation-map.json)도 만들어 올린다.

만드는 대원
- 대원 1: 정상 보정(done). 사각형을 한 바퀴 돈다. 영상 조각 2개
- 대원 2: 일부 보정(partial). 중간에 구간이 끊기고 추적이 끊긴 구간이 있다. 영상 조각 2개
- 대원 3: 보정 실패(failed). 영상 조각 1개
- 대원 4: 기록은 끝났지만 result.json과 영상이 없다

영상 조각은 ffmpeg로 만든다. 화면에 대원 이름과 영상 시각이 보여 타임라인과 맞는지 눈으로 확인할 수 있다.
글자를 그릴 수 없는 ffmpeg(drawtext 없음)면 조각마다 0초부터 세는 시계만 보인다.
ffmpeg가 없거나 `--no-video`를 주면 영상 없이 넣는다.
"""

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

PROJECT = "cqb-wffmst"
BUCKET = f"{PROJECT}.firebasestorage.app"


def request(method, url, body=None, content_type="application/json"):
    data = body if isinstance(body, bytes) or body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer owner")
    if data is not None:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {url} 실패 {error.code}: {error.read()[:300]!r}")
    except urllib.error.URLError as error:
        raise SystemExit(f"에뮬레이터에 연결하지 못했습니다. firebase emulators:start 를 먼저 실행하세요. ({error.reason})")


def value(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, datetime):
        return {"timestampValue": v.isoformat().replace("+00:00", "Z")}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: value(x) for k, x in v.items()}}}
    raise TypeError(v)


def write_document(host, path, fields):
    url = f"http://{host}:8080/v1/projects/{PROJECT}/databases/(default)/documents/{path}"
    request("PATCH", url, {"fields": {k: value(v) for k, v in fields.items()}})


def upload_file(host, path, data, content_type="application/json"):
    name = urllib.parse.quote(path, safe="")
    request("POST", f"http://{host}:9199/v0/b/{BUCKET}/o?uploadType=media&name={name}", data, content_type)


def make_chunks(ffmpeg, directory, name, durations, audio_frequency):
    """대원 이름·영상 시각과 구분 가능한 AAC 시험음이 있는 mp4 조각을 만든다."""
    files, elapsed = [], 0.0
    for index, seconds in enumerate(durations):
        path = f"{directory}/{name.replace(' ', '')}_{index}.mp4"
        label = f"drawtext=text='{name.replace(' ', '')}  %{{eif\\:t+{elapsed}\\:d}}s':fontsize=48:fontcolor=white:x=40:y=40"
        command = [ffmpeg, "-loglevel", "error", "-y",
                   "-f", "lavfi", "-i", f"testsrc2=s=640x360:r=15:d={seconds}",
                   "-f", "lavfi", "-i", f"sine=frequency={audio_frequency}:sample_rate=48000:duration={seconds}",
                   "-vf", label, "-filter:a", "volume=0.35", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                   "-c:a", "aac", "-profile:a", "aac_low", "-ac", "1", "-b:a", "64k", "-shortest", path]
        if subprocess.run(command, stderr=subprocess.DEVNULL).returncode != 0:
            # 글자를 그릴 수 없는 ffmpeg(drawtext 없음)면 조각마다 0초부터 세는 시계가 있는 기본 화면으로 만든다.
            command[command.index("-vf"):command.index("-vf") + 2] = []
            command[command.index("-i") + 1] = f"testsrc=s=640x360:r=15:d={seconds}"
            subprocess.run(command, check=True)
        files.append(path)
        elapsed += seconds
    return files


def png(width, height, pixel):
    """pixel(x, y) -> (r, g, b)로 RGB PNG를 만든다."""
    rows = b"".join(b"\x00" + bytes(c for x in range(width) for c in pixel(x, y)) for y in range(height))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def seed_floor_plan(host, width, height):
    """바깥 벽과 50px 격자가 있는 시험 도면 파일 3개를 올리고 FloorPlanReference를 돌려준다."""
    floor_plan_id = str(uuid.uuid4()).upper()
    wall = 12

    def pixel(x, y):
        if x < wall or y < wall or x >= width - wall or y >= height - wall:
            return (200, 200, 200)
        if x % 50 == 0 or y % 50 == 0:
            return (90, 90, 90)
        return (30, 30, 30)

    image = png(width, height, pixel)
    cell = 10
    columns, rows = (width + cell - 1) // cell, (height + cell - 1) // cell
    mask = bytes(1 if c == 0 or r == 0 or c == columns - 1 or r == rows - 1 else 0
                 for r in range(rows) for c in range(columns))
    manifest = {
        "schemaVersion": 1, "floorPlanID": floor_plan_id, "coordinateSystem": "image-pixel-top-left",
        "imageWidth": width, "imageHeight": height, "imageSHA256": hashlib.sha256(image).hexdigest(),
        "scale": {"a": {"x": wall, "y": wall}, "b": {"x": width - wall, "y": wall}, "meters": 20.0},
        "indoorOutline": [{"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 0.0}, {"x": 1.0, "y": 1.0}, {"x": 0.0, "y": 1.0}],
        "navigationGrid": {"columns": columns, "rows": rows, "cellSizePixels": cell, "encoding": "uint8-row-major",
                           "freeValue": 0, "blockedValue": 1, "outsideIsBlocked": True,
                           "maskSHA256": hashlib.sha256(mask).hexdigest()},
        "extractionAlgorithmVersion": "seed", "rasterizationVersion": 2, "manuallyReviewed": True,
    }
    navigation = json.dumps(manifest, sort_keys=True).encode()
    upload_file(host, f"floorPlans/{floor_plan_id}/original.png", image, "image/png")
    upload_file(host, f"floorPlans/{floor_plan_id}/resolved-mask.bin", mask, "application/octet-stream")
    upload_file(host, f"floorPlans/{floor_plan_id}/navigation-map.json", navigation, "application/json")
    return {"floorPlanID": floor_plan_id, "navigationSHA256": hashlib.sha256(navigation).hexdigest()}


def vertex(t, x, y, part, index):
    return {"t": t, "point": {"x": x, "y": y}, "part": part, "sampleIndex": index, "provenance": "correctedSample"}


def track_result(identity, floor_plan, status, vertices, unresolved=()):
    return {
        "schemaVersion": 1,
        "identity": identity,
        "floorPlan": floor_plan,
        "sourceRawSHA256": "seed",
        "algorithm": {"name": "seed", "version": "1", "settingsID": "seed"},
        "status": status,
        "vertices": vertices,
        "sampleCoverage": [],
        "unresolvedIntervals": list(unresolved),
        "searchIncomplete": False,
        "warnings": ["trackingLost"] if unresolved else [],
        **({"failureReason": "trackingLost"} if status == "failed" else {}),
    }


def square_path(width, height, seconds):
    """도면 안쪽 사각형을 seconds초 동안 한 바퀴 돈다."""
    left, top, right, bottom = width * 0.2, height * 0.2, width * 0.8, height * 0.8
    corners = [(left, top), (right, top), (right, bottom), (left, bottom), (left, top)]
    step = seconds / (len(corners) - 1)
    return [vertex(round(i * step, 2), x, y, 0, i) for i, (x, y) in enumerate(corners)]


def broken_path(width, height):
    """두 구간(part 0, 1)으로 나뉘고 12~15초에 추적이 끊긴 경로."""
    first = [vertex(t, width * (0.3 + t * 0.02), height * 0.5, 0, i) for i, t in enumerate([0, 5, 10])]
    second = [vertex(t, width * 0.6, height * (0.5 - (t - 20) * 0.015), 1, i + 3) for i, t in enumerate([20, 25, 30])]
    unresolved = [{
        "from": 12.0, "to": 15.0, "bounds": "[]", "reason": "trackingLost",
        "samples": {"from": 2, "through": 3},
    }]
    return first + second, unresolved


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="localhost", help="에뮬레이터 주소 (기본 localhost)")
    parser.add_argument("--instructor-uid", default="seed-instructor", help="세션의 instructorUid. 교관 앱 uid를 넣는다")
    parser.add_argument("--floor-plan-id", help="이미 등록한 도면 ID. 없으면 시험 도면을 만들어 올린다")
    parser.add_argument("--navigation-sha256", help="--floor-plan-id 도면의 navigationSHA256")
    parser.add_argument("--width", type=int, default=1000, help="도면 이미지 가로 픽셀")
    parser.add_argument("--height", type=int, default=800, help="도면 이미지 세로 픽셀")
    parser.add_argument("--no-video", action="store_true", help="영상 조각을 넣지 않는다")
    args = parser.parse_args()

    ffmpeg = None if args.no_video else shutil.which("ffmpeg")
    if not args.no_video and ffmpeg is None:
        print("ffmpeg가 없어 영상 없이 넣습니다. (brew install ffmpeg)", file=sys.stderr)

    session_id = str(uuid.uuid4()).upper()
    pin = f"{uuid.uuid4().int % 900000 + 100000}"
    if args.floor_plan_id:
        if not args.navigation_sha256:
            raise SystemExit("--floor-plan-id에는 --navigation-sha256도 함께 넣어야 합니다.")
        floor_plan = {"floorPlanID": args.floor_plan_id.upper(), "navigationSHA256": args.navigation_sha256}
    else:
        floor_plan = seed_floor_plan(args.host, args.width, args.height)
    started_at = datetime.now(timezone.utc) - timedelta(minutes=2)

    write_document(args.host, f"sessions/{session_id}", {
        "id": session_id, "pin": pin, "name": "AAR 시험 훈련", "status": "ended",
        "startedAt": started_at, "floorPlan": floor_plan, "instructorUid": args.instructor_uid,
    })

    broken, unresolved = broken_path(args.width, args.height)
    # (이름, 기록 시작 오프셋, 보정 결과, 꼭짓점, 끊긴 구간, 영상 조각 길이)
    members = [
        ("대원 1", 2.0, "done", square_path(args.width, args.height, 40), [], [20, 20], 420),
        ("대원 2", 3.5, "partial", broken, unresolved, [15, 15], 440),
        ("대원 3", 5.0, "failed", [], [], [10], 460),
        ("대원 4", 1.0, None, None, [], [12], 640),
        ("대원 5", 2.5, "done", square_path(args.width, args.height, 60), [], [12], 660),
        ("대원 6", 4.0, "done", square_path(args.width, args.height, 80), [], [12], 680),
    ]
    summary = {"sessionID": session_id, "pin": pin, "floorPlan": floor_plan, "members": []}

    # 중간에 실패해도 만든 영상 조각을 지운다.
    video_dir = tempfile.mkdtemp(prefix="cqb-aar-seed-")
    try:
        for name, offset, status, vertices, gaps, chunk_seconds, audio_frequency in members:
            member_id, recording_id = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
            identity = {"sessionID": session_id, "memberID": member_id, "recordingID": recording_id}
            write_document(args.host, f"sessions/{session_id}/members/{member_id}", {
                "id": member_id, "sessionID": session_id, "name": name, "isReady": True,
                "lastActiveAt": started_at, "uid": f"seed-{member_id}", "pin": pin,
            })
            chunks = make_chunks(
                ffmpeg, video_dir, name, chunk_seconds, audio_frequency
            ) if ffmpeg and chunk_seconds else []
            for index, chunk in enumerate(chunks):
                with open(chunk, "rb") as file:
                    upload_file(args.host, f"sessions/{session_id}/recordings/{recording_id}/video/chunk_{index:04d}.mp4",
                                file.read(), "video/mp4")
            write_document(args.host, f"sessions/{session_id}/recordings/{recording_id}", {
                "identity": identity, "state": "done", "startedAt": started_at + timedelta(seconds=offset),
                "lastActiveAt": started_at + timedelta(seconds=60), "videoChunkCount": len(chunks),
            })
            if status is not None:
                document = track_result(identity, floor_plan, status, vertices, gaps)
                upload_file(args.host, f"sessions/{session_id}/recordings/{recording_id}/result.json",
                            json.dumps(document, ensure_ascii=False, sort_keys=True).encode(), "application/json")
            summary["members"].append({"name": name, "result": status or "없음", "videoChunks": len(chunks),
                                       "recordingOffset": offset, **identity})
    finally:
        shutil.rmtree(video_dir, ignore_errors=True)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
