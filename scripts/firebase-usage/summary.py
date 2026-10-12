"""relay.py의 요청별 기록을 md 표로 정리한다. relay.py가 3초마다 불러 쓴다.

따로 다시 만들려면:

    python3 summary.py <날짜_시각>_traffic.jsonl > 결과.md
"""
import json
import os
import sys
import time
from collections import defaultdict

MB = 1024 * 1024


def classify(entry):
    """Storage 요청을 (대상, 동작)으로 나눈다. 경로는 docs/repositories.md의 Storage 경로를 따른다."""
    path = entry["path"] + "/" + entry["name"]
    if "floorPlans/" in path:
        target = "도면"
    elif "/video/" in path:
        target = "영상 조각"
    elif path.endswith("result.json"):
        target = "동선 결과"
    else:
        target = "기타"
    if entry["method"] == "DELETE":
        action = "지우기"
    elif entry["method"] == "GET":
        action = "받기" if entry["alt"] == "media" else "정보 확인"
    else:
        action = "올리기"
    return target, action


def size(value):
    return f"{value / MB:.2f}MB" if value >= MB / 10 else f"{value / 1024:.1f}KB"


def render(log_path, stamp, totals=None):
    """stamp: 측정 시작 `%Y-%m-%d_%H%M`. totals: relay.py의 기기·서비스별 누적(열린 연결 포함)."""
    rows = defaultdict(lambda: {"count": 0, "up": 0, "down": 0, "failed": 0})
    if os.path.exists(log_path):
        for line in open(log_path):
            entry = json.loads(line)
            if entry["service"] != "storage":
                continue
            row = rows[(entry["client"],) + classify(entry)]
            row["count"] += 1
            row["up"] += entry["requestBytes"]
            row["down"] += entry["responseBytes"]
            row["failed"] += entry["status"] >= 400

    started = time.strptime(stamp, "%Y-%m-%d_%H%M")
    lines = [
        f"# Firebase 사용량 측정 {time.strftime('%Y-%m-%d %H:%M', started)}",
        "",
        f"- 측정 시간: {time.strftime('%H:%M', started)} ~ {time.strftime('%H:%M:%S')} (마지막 갱신)",
        "",
        "## Storage (요청별)",
        "",
        "| 기기 | 대상 | 동작 | 요청 수 | 기기→서버 | 서버→기기 | 실패 |",
        "|---|---|---|---|---|---|---|",
    ]
    for (client, target, action), row in sorted(rows.items()):
        lines.append(f"| {client} | {target} | {action} | {row['count']} | {size(row['up'])} | {size(row['down'])} | {row['failed']} |")
    if totals:
        lines += ["", "## 서비스별 누적 (열려 있는 연결 포함)", "",
                  "| 기기 | 서비스 | 기기→서버 | 서버→기기 |", "|---|---|---|---|"]
        for key, row in sorted(totals.items()):
            service, client = key.split(" ", 1)
            lines.append(f"| {client} | {service} | {size(row['uploadBytes'])} | {size(row['downloadBytes'])} |")
    lines += [
        "",
        "- 기기 IP가 맥 IP면 같은 맥의 시뮬레이터, 그 밖은 실기기다.",
        "- 올리기 한 번은 보통 요청 2개(시작 + 전송)다.",
        "- Firestore는 gRPC라 요청 수 대신 주고받은 바이트만 센다. 요금 기준(문서 읽기·쓰기 수)과는 다르다.",
    ]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    path = sys.argv[1]
    print(render(path, os.path.basename(path).replace("_traffic.jsonl", "")), end="")
