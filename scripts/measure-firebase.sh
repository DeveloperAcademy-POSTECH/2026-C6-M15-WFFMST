#!/bin/bash
# Firebase 에뮬레이터를 맥 안(127.0.0.1)에서만 켜고, 맥 IP에 사용량 측정 중계기를 붙인다.
# 기기는 평소처럼 맥 IP로 접속하고, 주고받은 양은 md로 남는다. Ctrl+C로 둘 다 끈다.
#
#   scripts/measure-firebase.sh [맥 IP]
#
# - 맥 IP를 빼면 en0(와이파이)의 IP를 쓴다.
# - md 폴더는 CQB_USAGE_DIR (기본 ~/Documents/cqb-traffic)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
host="${1:-$(ipconfig getifaddr en0 || true)}"
out_dir="${CQB_USAGE_DIR:-$HOME/Documents/cqb-traffic}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/cqb-firebase-usage.XXXXXX")"

if [ -z "$host" ]; then
  echo "맥 IP를 찾지 못했습니다. 와이파이 연결을 확인하거나 IP를 넣어 실행하세요: $0 192.168.0.12" >&2
  exit 1
fi
if [ -d /opt/homebrew/opt/openjdk@21/bin ]; then
  export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
fi

# 루트 firebase.json과 같고 주소만 127.0.0.1이다. 0.0.0.0이면 중계기가 맥 IP의 같은 포트를 쓸 수 없다.
cat > "$work_dir/firebase.json" <<EOF
{
  "firestore": { "rules": "$repo_root/firebase/firestore.rules" },
  "storage": { "rules": "$repo_root/firebase/storage.rules" },
  "emulators": {
    "auth": { "host": "127.0.0.1", "port": 9099 },
    "firestore": { "host": "127.0.0.1", "port": 8080 },
    "storage": { "host": "127.0.0.1", "port": 9199 },
    "ui": { "enabled": true, "port": 4000 },
    "singleProjectMode": true
  }
}
EOF

emulator_pid=""
relay_pid=""
cleanup() {
  [ -n "$relay_pid" ] && kill "$relay_pid" 2>/dev/null || true
  [ -n "$emulator_pid" ] && kill "$emulator_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf "$work_dir"
}
trap cleanup EXIT
# Ctrl+C는 정상 종료로 본다. 정리는 EXIT에서 한 번만 한다.
trap 'exit 0' INT TERM

echo "에뮬레이터를 켜는 중... (로그: $work_dir/emulator.log)"
(cd "$repo_root" && firebase emulators:start --project cqb-wffmst --config "$work_dir/firebase.json") \
  > "$work_dir/emulator.log" 2>&1 &
emulator_pid=$!

# 중계기는 에뮬레이터가 다 켜진 뒤에 켠다. 먼저 켜면 에뮬레이터가 포트가 쓰이는 중이라며 멈춘다.
for _ in $(seq 120); do
  grep -q "All emulators ready" "$work_dir/emulator.log" && break
  if ! kill -0 "$emulator_pid" 2>/dev/null; then
    cat "$work_dir/emulator.log" >&2
    echo "에뮬레이터가 켜지지 않았습니다. 다른 에뮬레이터가 켜져 있는지 확인하세요." >&2
    exit 1
  fi
  sleep 1
done
if ! grep -q "All emulators ready" "$work_dir/emulator.log"; then
  echo "에뮬레이터가 2분 안에 켜지지 않았습니다. 로그: $work_dir/emulator.log" >&2
  exit 1
fi

python3 "$repo_root/scripts/firebase-usage/relay.py" --host "$host" --out "$out_dir" --raw "$work_dir/raw" &
relay_pid=$!

cat <<EOF

준비됐습니다. 기기는 FIREBASE_EMULATOR_HOST=$host 로 실행하세요.
- 실기기: 개인 (Emulator Device) 스킴 (값: $host)
- 시뮬레이터도 localhost 대신 $host 로 붙여야 기록됩니다.
관리 화면: http://localhost:4000   끄기: Ctrl+C
EOF
wait "$relay_pid"
