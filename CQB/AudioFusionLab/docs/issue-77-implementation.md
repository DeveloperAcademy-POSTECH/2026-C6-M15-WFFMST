# #77 다중 기기 오디오 융합 검증 앱

## 목적

`AudioFusionLab`은 제품 앱에 총성 탐지 정책을 넣기 전에 Apple 내장 Sound Classifier의 기기별 결과와 다중 기기 시간 일치 조건을 파일 기반으로 검증하는 독립 iPhone 앱이다.

이 타깃은 `MemberApp`, `InstructorApp`, `CQBCore`, Firebase 데이터 계약에 의존하지 않는다. 실험 결과가 유효할 때만 별도 제품 이슈에서 검증된 부분을 이식한다.

## 현재 범위

1. ARKit world tracking session을 실행하고 `providesAudioData`를 활성화한다.
2. ARKit audio sample buffer를 PCM CAF 파일로 저장한다.
3. 녹음 종료 후 Apple 내장 sound classifier version 1을 overlap 50%로 실행한다.
4. 임계값 적용 전 전체 분류 label과 confidence를 기록한다.
5. 분류 결과의 오디오 파일 시간을 첫 AR frame 기준 기록 내부 시간으로 변환한다.
6. 사용자가 동기화·격발 후보·기타 마커를 같은 기록 내부 시간으로 남길 수 있다.
7. metadata JSON, PCM CAF, classifications CSV, manual markers CSV를 Share Sheet로 내보낸다.
8. `scripts/audio_fusion/analyze_fusion.py`로 여러 기기의 결과를 동기화하고 N-of-M 조건별 지표를 계산한다.

## 시간 기준

- 기록 내부 `0초`: 사용자가 녹음을 시작할 때의 현재 `ARFrame.timestamp`
- 오디오 파일 `0초`: 첫 audio sample buffer의 presentation timestamp
- `audioStartOffsetSeconds`: 첫 audio PTS에서 기록 시작 AR timestamp를 뺀 값
- 분류 이벤트 기록 시각: `audioStartOffsetSeconds + SNClassificationResult.timeRange.start`

`ARFrame.timestamp`와 audio PTS가 동일 host clock에 대응하는지는 실기기에서 시작·종료 동기화음으로 검증해야 한다. 여러 기기의 공통 세션 시간 정렬과 clock drift 보정은 이 앱이 내보낸 파일을 사용하는 후속 오프라인 분석 범위다.

오프라인 분석은 한 기기를 기준 시간축으로 정하고 기기별 `sync` 마커를 순서대로 대응시킨다. 마커가 하나면 offset만 보정하고, 시작·종료를 포함해 두 개 이상이면 선형 회귀로 offset과 clock drift를 함께 보정한다. 따라서 모든 기기에서 같은 동기화음을 들은 직후 동일한 순서로 `동기화` 버튼을 눌러야 한다.

## 파일 구조

```text
Application Support/AudioFusionLab/<sessionID>/<deviceID>-<recording-time>/
├── audio.caf
├── metadata.json
├── classifications.csv
└── manual-markers.csv
```

## 오프라인 융합 분석

각 기기에서 내보낸 네 파일을 기기별 디렉터리에 모은 뒤 저장소 루트에서 실행한다.

```bash
python3 scripts/audio_fusion/analyze_fusion.py \
  --recording /path/to/device-a-recording \
  --recording /path/to/device-b-recording \
  --reference-device device-a \
  --ground-truth-device device-a \
  --confidence 0.1 \
  --fusion-tolerance 0.5 \
  --match-tolerance 1.0 \
  --output /path/to/analysis-output
```

- `--reference-device`: 공통 시간축으로 사용할 `metadata.json`의 `deviceID`
- `--ground-truth-device`: `shotCandidate` 정답 마커를 기록한 기기
- `--confidence`: 내장 분류기 후보를 남길 최소 confidence
- `--device-merge-gap`: 한 기기의 연속 윈도를 한 이벤트로 합칠 간격, 기본 `0.45초`
- `--fusion-tolerance`: 서로 다른 기기의 후보를 같은 이벤트로 볼 시간 허용치, 기본 `0.5초`
- `--match-tolerance`: 탐지와 정답 마커를 TP로 대응시킬 시간 허용치, 기본 `1.0초`
- `--min-devices`: 생략하면 1개부터 전체 기기까지 모든 N-of-M 조건을 계산하며 여러 번 지정할 수 있다.

결과 디렉터리에는 다음 파일이 생성된다.

- `alignment.csv`: 기기별 offset, drift scale, 동기화 마커 잔차
- `device-events.csv`: 반복 분류 윈도를 합친 기기별 후보
- `fused-events.csv`: 같은 시간대의 기기별 후보를 합친 이벤트와 참여 기기 수
- `metrics.csv`: N-of-M별 Precision, Recall, F1, FP/min, timestamp bias·MAE·P95
- `report.json`: 분석 입력값과 지표 요약

`shotCandidate`는 자동 정답이 아니다. 실험 후 파형·영상으로 확인한 정답 시각을 기준 기기의 marker CSV에 반영한 뒤 최종 지표를 계산한다.

## 의도적으로 제외한 항목

- 실시간 다중 기기 통신·융합
- 커스텀 Create ML 모델
- 가속도·자이로 판정
- Firebase 업로드
- AAR 타임라인 표시
- 자동 ground truth 확정

## 실기기 확인 항목

- 카메라·마이크 권한 승인 및 거절 흐름
- ARKit 실행 중 CAF에 실제 오디오 트랙이 기록되는지
- 30초 이상 기록 후 SoundAnalysis가 파일을 끝까지 분석하는지
- 시작·종료 동기화음의 기록 내부 시각이 실제 파형과 일치하는지
- 기기 잠금, 앱 전환, 전화 등 interruption 발생 시 부분 파일 처리 여부
- 실제 iPhone 두 대 이상의 파일을 내보내 동일 세션으로 식별할 수 있는지
