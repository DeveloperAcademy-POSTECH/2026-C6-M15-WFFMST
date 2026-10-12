#!/usr/bin/env python3
"""Firebase 에뮬레이터에 AAR 시험용 세션·대원·기록과 보정 결과(result.json)를 넣는다.

에뮬레이터 관리자 권한(Bearer owner)으로 보안 규칙을 거치지 않고 바로 쓴다. 운영 Firebase에는 쓰지 않는다.

    firebase emulators:start            # 다른 터미널에서 먼저 켠다
    python3 scripts/seed-aar-emulator.py --instructor-uid <교관 앱 uid>

교관 앱이 세션을 읽으려면 `--instructor-uid`에 교관 앱의 익명 로그인 uid를 넣는다.
uid는 교관 앱을 (Emulator) 스킴으로 실행한 뒤 http://localhost:4000/auth 에서 확인한다.

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
import json
import shutil
import subprocess
import sys
import tempfile
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


def upload_file(host, path, data, content_type):
    name = urllib.parse.quote(path, safe="")
    request("POST", f"http://{host}:9199/v0/b/{BUCKET}/o?uploadType=media&name={name}", data, content_type)


def make_chunks(ffmpeg, directory, name, durations):
    """대원 이름과 영상 시각(초)이 보이는 mp4 조각을 만든다."""
    files, elapsed = [], 0.0
    for index, seconds in enumerate(durations):
        path = f"{directory}/{name.replace(' ', '')}_{index}.mp4"
        label = f"drawtext=text='{name.replace(' ', '')}  %{{eif\\:t+{elapsed}\\:d}}s':fontsize=48:fontcolor=white:x=40:y=40"
        command = [ffmpeg, "-loglevel", "error", "-y", "-f", "lavfi", "-i", f"testsrc2=s=640x360:r=15:d={seconds}",
                   "-vf", label, "-c:v", "libx264", "-pix_fmt", "yuv420p", path]
        if subprocess.run(command, stderr=subprocess.DEVNULL).returncode != 0:
            # 글자를 그릴 수 없는 ffmpeg(drawtext 없음)면 조각마다 0초부터 세는 시계가 있는 기본 화면으로 만든다.
            command[command.index("-vf"):command.index("-vf") + 2] = []
            command[command.index("-i") + 1] = f"testsrc=s=640x360:r=15:d={seconds}"
            subprocess.run(command, check=True)
        files.append(path)
        elapsed += seconds
    return files


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
    parser.add_argument("--floor-plan-id", default=str(uuid.uuid4()).upper(), help="세션 도면 ID (등록한 도면과 맞출 때)")
    parser.add_argument("--navigation-sha256", default="seed-navigation", help="세션 도면의 navigationSHA256")
    parser.add_argument("--width", type=float, default=1000, help="도면 이미지 가로 픽셀")
    parser.add_argument("--height", type=float, default=800, help="도면 이미지 세로 픽셀")
    parser.add_argument("--no-video", action="store_true", help="영상 조각을 넣지 않는다")
    args = parser.parse_args()

    ffmpeg = None if args.no_video else shutil.which("ffmpeg")
    if not args.no_video and ffmpeg is None:
        print("ffmpeg가 없어 영상 없이 넣습니다. (brew install ffmpeg)", file=sys.stderr)
    video_dir = tempfile.mkdtemp(prefix="cqb-aar-seed-")

    session_id = str(uuid.uuid4()).upper()
    pin = f"{uuid.uuid4().int % 900000 + 100000}"
    floor_plan = {"floorPlanID": args.floor_plan_id.upper(), "navigationSHA256": args.navigation_sha256}
    started_at = datetime.now(timezone.utc) - timedelta(minutes=2)

    write_document(args.host, f"sessions/{session_id}", {
        "id": session_id, "pin": pin, "name": "AAR 시험 훈련", "status": "ended",
        "startedAt": started_at, "floorPlan": floor_plan, "instructorUid": args.instructor_uid,
    })

    broken, unresolved = broken_path(args.width, args.height)
    # (이름, 기록 시작 오프셋, 보정 결과, 꼭짓점, 끊긴 구간, 영상 조각 길이)
    members = [
        ("대원 1", 2.0, "done", square_path(args.width, args.height, 40), [], [20, 20]),
        ("대원 2", 3.5, "partial", broken, unresolved, [15, 15]),
        ("대원 3", 5.0, "failed", [], [], [10]),
        ("대원 4", 1.0, None, None, [], []),
    ]
    summary = {"sessionID": session_id, "pin": pin, "floorPlan": floor_plan, "members": []}

    for name, offset, status, vertices, gaps, chunk_seconds in members:
        member_id, recording_id = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
        identity = {"sessionID": session_id, "memberID": member_id, "recordingID": recording_id}
        write_document(args.host, f"sessions/{session_id}/members/{member_id}", {
            "id": member_id, "sessionID": session_id, "name": name, "isReady": True,
            "lastActiveAt": started_at, "uid": f"seed-{member_id}", "pin": pin,
        })
        chunks = make_chunks(ffmpeg, video_dir, name, chunk_seconds) if ffmpeg and chunk_seconds else []
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

    shutil.rmtree(video_dir, ignore_errors=True)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
