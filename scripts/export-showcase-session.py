#!/usr/bin/env python3
"""쇼케이스 데모용 실제 세션 파일을 교관 앱 PrivateDemo 폴더로 옮긴다 (#252).

입력 폴더 구조 (운영 Firebase에서 읽기 전용으로 받은 것):
  <input>/session.json      Firestore REST 응답 (sessions/{id})
  <input>/members.json      Firestore REST 응답 (sessions/{id}/members)
  <input>/recordings.json   Firestore REST 응답 (sessions/{id}/recordings)
  <input>/storage/<sessionID>/recordings/<recordingID>/{result.json,sound-candidates.json,video/chunk_NNNN.mp4}
  <input>/floorPlan/<floorPlanID>/{original.png,navigation-map.json,resolved-mask.bin}

출력: CQB/InstructorApp/Resources/PrivateDemo/ (gitignore, 커밋 금지)
  Xcode 폴더 동기화가 하위 폴더를 번들 루트로 펼치므로 파일 이름을 겹치지 않게 바꾼다.
  세션마다 아래 파일을 만들고, 같은 세션의 이전 파일만 지운다. 다른 세션 파일은 그대로 둔다.
  ShowcaseSession-<sessionID>.json, ShowcaseFloorPlan-<floorPlanID>-{original.png,navigation-map.json,resolved-mask.bin},
  Showcase-<recordingID>-{result.json,sound.json,chunk_NNNN.mp4}
교관 uid, PIN, 대원 uid는 옮기지 않는다.
"""
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUTPUT = REPO / "CQB/InstructorApp/Resources/PrivateDemo"


def value(v):
    kind, raw = next(iter(v.items()))
    if kind == "mapValue":
        return {k: value(x) for k, x in raw.get("fields", {}).items()}
    if kind == "arrayValue":
        return [value(x) for x in raw.get("values", [])]
    if kind == "integerValue":
        return int(raw)
    return raw


def fields(doc):
    return {k: value(v) for k, v in doc["fields"].items()}


def epoch(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()


def main(source: Path, floor_plan_name: str):
    session = fields(json.loads((source / "session.json").read_text()))
    members = [fields(d) for d in json.loads((source / "members.json").read_text())["documents"]]
    recordings = [fields(d) for d in json.loads((source / "recordings.json").read_text())["documents"]]
    session_id = session["id"]
    floor_plan = session["floorPlan"]

    OUTPUT.mkdir(parents=True, exist_ok=True)
    old = OUTPUT / f"ShowcaseSession-{session_id}.json"
    if old.exists():
        for entry in json.loads(old.read_text())["members"]:
            for path in OUTPUT.glob(f"Showcase-{entry['recordingID']}-*"):
                path.unlink()
        old.unlink()

    plan_id = floor_plan["floorPlanID"]
    plan_dir = source / "floorPlan" / plan_id
    for name in ("original.png", "navigation-map.json", "resolved-mask.bin"):
        shutil.copy(plan_dir / name, OUTPUT / f"ShowcaseFloorPlan-{plan_id}-{name}")

    names = {m["id"]: m["name"] for m in members}
    entries = []
    for rec in sorted(recordings, key=lambda r: names.get(r["identity"]["memberID"], "")):
        identity = rec["identity"]
        rid = identity["recordingID"]
        rec_dir = source / "storage" / session_id / "recordings" / rid
        chunks = int(rec["videoChunkCount"])
        result = json.loads((rec_dir / "result.json").read_text())
        result["identity"] = identity  # 앱이 요청한 세션, 대원, 녹화와 맞춘다
        (OUTPUT / f"Showcase-{rid}-result.json").write_text(json.dumps(result, ensure_ascii=False))
        if (rec_dir / "sound-candidates.json").exists():
            shutil.copy(rec_dir / "sound-candidates.json", OUTPUT / f"Showcase-{rid}-sound.json")
        for index in range(chunks):
            name = f"chunk_{index:04d}.mp4"
            shutil.copy(rec_dir / "video" / name, OUTPUT / f"Showcase-{rid}-{name}")
        entries.append({
            "memberID": identity["memberID"],
            "recordingID": rid,
            "name": names[identity["memberID"]],
            "startedAt": epoch(rec["startedAt"]),
            "videoChunkCount": chunks,
        })

    manifest = {
        "sessionID": session_id,
        "name": session["name"],
        "floorPlanName": floor_plan_name,
        "startedAt": epoch(session["startedAt"]),
        "endedAt": max(epoch(r["lastActiveAt"]) for r in recordings),
        "floorPlan": {
            "floorPlanID": floor_plan["floorPlanID"],
            "navigationSHA256": floor_plan["navigationSHA256"],
        },
        "members": entries,
    }
    (OUTPUT / f"ShowcaseSession-{session_id}.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    total = sum(p.stat().st_size for p in OUTPUT.iterdir())
    print(f"{OUTPUT}: {len(list(OUTPUT.iterdir()))}개 파일, {total / 1_048_576:.1f} MiB")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("사용법: export-showcase-session.py <받은 세션 폴더> <도면 이름>")
    main(Path(sys.argv[1]), sys.argv[2])
