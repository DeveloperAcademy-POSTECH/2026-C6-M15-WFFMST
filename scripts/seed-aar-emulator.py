#!/usr/bin/env python3
"""Firebase 에뮬레이터에 AAR 시험용 세션·대원·기록과 보정 결과(result.json)를 넣는다.

에뮬레이터 관리자 권한(Bearer owner)으로 보안 규칙을 거치지 않고 바로 쓴다. 운영 Firebase에는 쓰지 않는다.

    firebase emulators:start            # 다른 터미널에서 먼저 켠다
    python3 scripts/seed-aar-emulator.py --instructor-uid <교관 앱 uid>

교관 앱이 세션을 읽으려면 `--instructor-uid`에 교관 앱의 익명 로그인 uid를 넣는다.
uid는 교관 앱을 (Emulator) 스킴으로 실행한 뒤 http://localhost:4000/auth 에서 확인한다.

만드는 대원
- 대원 1: 정상 보정(done). 사각형을 한 바퀴 돈다
- 대원 2: 일부 보정(partial). 중간에 구간이 끊기고 추적이 끊긴 구간이 있다
- 대원 3: 보정 실패(failed)
- 대원 4: 기록은 끝났지만 result.json이 없다
"""

import argparse
import json
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


def upload_file(host, path, data):
    name = urllib.parse.quote(path, safe="")
    request("POST", f"http://{host}:9199/v0/b/{BUCKET}/o?uploadType=media&name={name}", data)


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
    args = parser.parse_args()

    session_id = str(uuid.uuid4()).upper()
    pin = f"{uuid.uuid4().int % 900000 + 100000}"
    floor_plan = {"floorPlanID": args.floor_plan_id.upper(), "navigationSHA256": args.navigation_sha256}
    started_at = datetime.now(timezone.utc) - timedelta(minutes=2)

    write_document(args.host, f"sessions/{session_id}", {
        "id": session_id, "pin": pin, "name": "AAR 시험 훈련", "status": "ended",
        "startedAt": started_at, "floorPlan": floor_plan, "instructorUid": args.instructor_uid,
    })

    broken, unresolved = broken_path(args.width, args.height)
    members = [
        ("대원 1", 2.0, "done", square_path(args.width, args.height, 40), []),
        ("대원 2", 3.5, "partial", broken, unresolved),
        ("대원 3", 5.0, "failed", [], []),
        ("대원 4", 1.0, None, None, []),
    ]
    summary = {"sessionID": session_id, "pin": pin, "floorPlan": floor_plan, "members": []}

    for name, offset, status, vertices, gaps in members:
        member_id, recording_id = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
        identity = {"sessionID": session_id, "memberID": member_id, "recordingID": recording_id}
        write_document(args.host, f"sessions/{session_id}/members/{member_id}", {
            "id": member_id, "sessionID": session_id, "name": name, "isReady": True,
            "lastActiveAt": started_at, "uid": f"seed-{member_id}", "pin": pin,
        })
        write_document(args.host, f"sessions/{session_id}/recordings/{recording_id}", {
            "identity": identity, "state": "done", "startedAt": started_at + timedelta(seconds=offset),
            "lastActiveAt": started_at + timedelta(seconds=60), "videoChunkCount": 0,
        })
        if status is not None:
            document = track_result(identity, floor_plan, status, vertices, gaps)
            upload_file(args.host, f"sessions/{session_id}/recordings/{recording_id}/result.json",
                        json.dumps(document, ensure_ascii=False, sort_keys=True).encode())
        summary["members"].append({"name": name, "result": status or "없음", "recordingOffset": offset, **identity})

    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
