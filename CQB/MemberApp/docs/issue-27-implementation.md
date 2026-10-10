# #27 ARKit 영상·동선 기록

## 처리 순서

`setup → waiting → recording → saving → correcting → saved → uploading(기존 시뮬레이션)`

1. `StartPositionSetupView`의 두 번 터치로 출발점과 방향을 선택한다. 선택값은 이미지 상대 좌표이며, Store에서 원본 이미지 픽셀로 변환한다. 이동 불가능한 출발점과 10px 미만의 방향 화살표는 거절한다.
2. `ARRecordingService`가 카메라 권한을 요청하고 단일 ARSession을 실행한다. 1초간 normal 상태이며 최근 0.5초의 카메라 수평 방향이 안정적이어야 시작할 수 있다. **선택한 출발점에서 선택한 방향을 바라보고 녹화를 시작해야 한다.**
3. 같은 ARFrame의 capturedImage는 `ARFrameVideoWriter`로, transform은 약 10Hz 원본 샘플로 기록한다. 영상 PTS와 동선 t는 동일한 첫 프레임 timestamp를 0초로 사용한다. 영상은 기존과 동일하게 무음이다.
4. 영상 마무리 후 원본 JSON을 먼저 저장한다. 영상 저장 실패 시에도 원본 동선 저장을 시도한다.
5. 백그라운드 작업에서 V13 contextAware(standard, 초기 방향 ±60°, 왕복·거리 형태 보존) 보정을 실행한다. UI 스레드는 차단하지 않는다.
6. 보정 결과를 기존 `TrackResultDocument`로 변환하고 저장한다. 원본 해시는 실제 저장된 JSON 바이트의 SHA-256이다. 후보 상세는 앱 내부 진단 파일에 별도로 보관한다.
7. 결과 화면에서 영상, 원본/보정 경로, 미해결 구간, 후보 진단을 확인하고 파일을 내보낼 수 있다. 동선 파일 저장 실패 시 동일한 원본으로 재시도한다.

## 로컬 파일

```text
Application Support/Recordings/<recordingID>/
  video.mov
  raw-track.json
  result.json
  correction-diagnostics.json   # 후보가 있을 때 생성
```

`RawTrackDocument`는 #27 범위의 MemberApp 로컬 형식이다. 원본 x/y/z, 상대 x/z, trackingState, segment, 시작 좌표/방향/회전, 축척, TrackIdentity/FloorPlanReference를 포함한다. 공유 모델 및 Firebase 저장 계약은 수정하지 않았다. 로컬 기록 디렉터리는 기기 백업에서 제외한다. 업로드·삭제 정책은 후속 작업이다.

## 테스트 도면

- 출처: `ARKItandMarkerTest-V13.zip`의 `floorplan.png`와 V13 `FloorPlanWallDetector`.
- 원본: 2172×724px, 23.11px/m 고정. MapScale은 231.1px / 10m로 표현한다.
- PNG 원본 SHA-256: `7c322c5509d011cbd177c7a9bcd506b3a2450ba8fda7455022be2681b80dbf54`.
- `training-map.pngdata`는 PNG 바이트 그대로다. Xcode PNG 최적화가 파일 해시를 바꾸지 않도록 확장자를 구분했다.
- V13 벽 추출 후 2px 셀 내 하나라도 벽이면 blocked로 처리하고 V13 실내 외곽선 밖을 차단했다. 1086×362 uint8 row-major mask, 0=free/1=blocked.
- `training-navigation.json`은 기존 `FloorPlanManifest` 형식이며 이미지/마스크 해시를 포함한다. navigation JSON 바이트 해시를 `FloorPlanReference`에 사용한다.
- `manuallyReviewed=false`: 실험용 자동 추출 지도이며 실제 현장 통행 가능성을 인증한 지도가 아니다.
- `BundledTrainingMapLoader`가 파일 무결성을 확인한다. 나중에 서버 파일 로더를 같은 `TrainingMap` 입력으로 연결한다.

## 단절 및 오류

- 추적 제한·불가 샘플은 상대 좌표를 nil로 남긴다. 추적 재개 시 segment를 증가시키며 0.5초 초과 프레임 공백도 단절로 기록한다.
- 원본 경로는 segment, 보정 경로는 part별로 그린다. 단절 양끝을 임의의 선으로 연결하지 않는다.
- `vertices`, `sampleCoverage`, `unresolvedIntervals`, `searchIncomplete`, 경고와 실패 상태를 공통 계약에 보존한다. 후보가 없으면 failed 결과를 저장한다.
- 세션 중단/인코더 실패/앱 비활성화 시 녹화를 종료하고 확보된 자료를 저장한다. 정상 저장·보정 중에는 자동 잠금을 방지한다.
- 앱 강제 종료와 시스템에 의한 프로세스 종료에서 복구하는 기능은 포함하지 않는다. 장시간 비활성 상태에서 보정은 운영체제에 의해 일시 정지될 수 있다.

## 임시 가정과 후속 연결

- 현재 참가 흐름이 PIN/이름만 받으므로 참가 때 생성한 임시 sessionID/memberID를 사용한다. 실제 서버 식별자 연결 시 Store 주입 지점을 교체해야 한다.
- 보정 완료와 서버 업로드 완료는 별개다. `RecordingState.done`을 로컬 저장 완료 의미로 설정하지 않는다.
- 보정 알고리즘 파일은 V13의 순수 계산 코드를 이식했다. 기존 baseline matcher는 contextAware의 좌표 변환/탐색 보조 함수를 위해 유지한다.

## 검증 기록

- MemberApp generic iOS Debug 빌드(`CODE_SIGNING_ALLOWED=NO`): 통과.
- 실기기 ARKit·카메라·저장 공간 부족·30분 연속 기록은 이 환경에서 실행하지 못했다.
- 실기기에서는 정상 시작/종료, 벽 근처/왕복 이동, 카메라 가림 후 추적 재개, 앱 전환, 저장 실패 후 재시도, 내보낸 JSON과 영상의 시간 일치를 확인해야 한다.
