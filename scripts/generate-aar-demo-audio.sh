#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
resource_dir="$task_root/CQB/InstructorApp/Resources/Demo"
source_video="$resource_dir/DEBRIEF-Demo-AAR.mp4"
frequencies=(420 440 460 640 660 680)

command -v ffmpeg >/dev/null || { echo "ffmpeg가 필요합니다." >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe가 필요합니다." >&2; exit 1; }

for index in 0 1 2 3 4 5; do
  member_number=$((index + 1))
  frequency="${frequencies[$index]}"
  destination="$resource_dir/DEBRIEF-Demo-AAR-$member_number.mp4"

  ffmpeg -loglevel error -y \
    -i "$source_video" \
    -f lavfi -i "sine=frequency=$frequency:sample_rate=48000:duration=12" \
    -filter:a volume=0.35 \
    -map 0:v:0 -map 1:a:0 \
    -c:v copy \
    -c:a aac -profile:a aac_low -ac 1 -b:a 64k \
    -shortest \
    "$destination"

  audio_description="$(ffprobe -v error -select_streams a:0 \
    -show_entries stream=codec_name,profile,channels \
    -of csv=p=0 "$destination")"
  if [[ "$audio_description" != "aac,LC,1" ]]; then
    echo "$destination 오디오 형식이 올바르지 않습니다: $audio_description" >&2
    exit 1
  fi
done

echo "AAR 대원 1~6 데모 AAC 영상 생성 완료"
