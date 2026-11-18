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
  ShowcaseSession.json, ShowcaseFloorPlan-*.{png,json,bin}, Showcase-<recordingID>-{result.json,sound.json,chunk_NNNN.mp4}
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


def main(source: Path):
    session = fields(json.loads((source / "session.json").read_text()))
    members = [fields(d) for d in json.loads((source / "members.json").read_text())["documents"]]
    recordings = [fields(d) for d in json.loads((source / "recordings.json").read_text())["documents"]]
    session_id = session["id"]
    floor_plan = session["floorPlan"]

    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True)

    plan_dir = source / "floorPlan" / floor_plan["floorPlanID"]
    shutil.copy(plan_dir / "original.png", OUTPUT / "ShowcaseFloorPlan-original.png")
    shutil.copy(plan_dir / "navigation-map.json", OUTPUT / "ShowcaseFloorPlan-navigation-map.json")
    shutil.copy(plan_dir / "resolved-mask.bin", OUTPUT / "ShowcaseFloorPlan-resolved-mask.bin")

    names = {m["id"]: m["name"] for m in members}
    entries = []
    for rec in sorted(recordings, key=lambda r: names.get(r["identity"]["memberID"], "")):
        identity = rec["identity"]
        rid = identity["recordingID"]
        rec_dir = source / "storage" / session_id / "recordings" / rid
        chunks = int(rec["videoChunkCount"])
        shutil.copy(rec_dir / "result.json", OUTPUT / f"Showcase-{rid}-result.json")
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
        "startedAt": epoch(session["startedAt"]),
        "endedAt": max(epoch(r["lastActiveAt"]) for r in recordings),
        "floorPlan": {
            "floorPlanID": floor_plan["floorPlanID"],
            "navigationSHA256": floor_plan["navigationSHA256"],
        },
        "members": entries,
    }
    (OUTPUT / "ShowcaseSession.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    total = sum(p.stat().st_size for p in OUTPUT.iterdir())
    print(f"{OUTPUT}: {len(list(OUTPUT.iterdir()))}개 파일, {total / 1_048_576:.1f} MiB")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("사용법: export-showcase-session.py <받은 세션 폴더>")
    main(Path(sys.argv[1]))
