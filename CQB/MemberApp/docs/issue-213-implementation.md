# #213 ARWorldMap 재인식 동선 보정

## 모드와 책임

- `MemberStore`가 녹화 시작 직전의 `positioningState`로 모드를 캡처하고, 비동기 녹화 시작이 성공한 경우에만 기록에 연결한다. `.automaticReady`는 `.worldMap`, 수동 설정은 `.manual`이다.
- 저장·보정 재시도는 동일한 모드를 사용한다. 세션을 떠나거나 초기화하면 모드도 지운다. 재인식 실패 후 수동 설정 전환은 기존 흐름을 사용한다.
- `RouteCorrectionService`는 모드를 matcher에 전달하고 기존 `TrackResultDocument`로 변환한다. 원본 좌표·서버 공통 계약은 변경하지 않는다.
- 과거 `raw-track.json`에는 모드가 없다. 앱 외 재실행에서는 호출자가 모드를 지정해야 하며, 생략하면 기존 수동 보정을 사용한다. 저장된 좌표만으로 모드를 추정하지 않는다.

## 재인식 모드 초기 탐색

1. 회전 후보는 `−30, −26, −22, −18, −14, −10, −6, −2, 0, 2, 6, 10, 14, 18, 22, 26, 30°`다.
2. 각 회전에 이동 없음 및 상하좌우 0.5m·1m를 조합한다. 총 153개다. 이동은 회전 후 도면 좌표축 기준이며, 실제 기록의 `pixelsPerMeter`로 픽셀로 변환한다.
3. 지도 밖·장애물인 출발점을 제외한다. 기존 사전 평가와 동일하게 샘플을 간추려 전체 이동 선분의 충돌 거리 비율을 구한다. 이 평가는 순위 계산용이며 정밀 탐색에서 모든 채택 선분을 다시 검사한다.
4. 사전 비용은 `충돌 거리 비율 + 0.002 × (회전/30°)² + 0.002 × 이동량(m)²`다. 각도 차이 6° 미만이면서 이동 차이 0.5m 미만인 조합을 유사 후보로 보고 상위 4개를 고른다.
5. 선택한 이동 후 출발점을 기준으로 `coherentOnly`를 실행한다. 추가로 원본 방향·이동 없음 후보를 확인하고, 최상위 조합 주변 ±2°·±4°를 ±30° 범위 안에서 탐색한다.
6. 작은 변형의 1.5m 제한은 **이동·회전을 적용한 기준 경로와의 차이**다. 누적 거리·왕복 보존 및 벽 검사는 기존 조건을 사용한다. `NonrigidRouteMatcher`는 이미 전달받은 출발점을 기준으로 재개·왕복·결과 검증을 수행하므로 변경하지 않았다.
7. 충분히 좋은 완주 후보가 없으면 기존 일반 탐색을 원본 출발점 및 ±60° 정책으로 실행한다. 이 단계에는 평행 이동을 추가하지 않는다. 두 탐색의 후보를 공통 평가로 비교한다.
8. 재인식 후보의 최종 비용에는 `0.02 × 이동량(m)²`를 더한다. 선택 후보의 출발점은 결과 진단의 `anchor`에도 반영한다. 원본은 변경하지 않는다.

이동 범위·간격·후보 수·비용 계수는 사용자와 확인한 두 기록의 실험 설정을 그대로 적용한 초기 값이다. 실제 위치 정답을 확보한 상태에서 검증·조정해야 한다. `done`은 제약을 만족하는 전체 경로가 생성됐다는 의미이며 위치 정답을 보장하지 않는다.

## 유지한 범위

- 수동 모드의 초기 ±60°/2° 평가, 출발점 고정, 변형·왕복 제약 및 일반 탐색을 유지한다.
- 전체 20초, 방향 0° 회당 최대 3초 / 나머지 1.5초, 최대 25회와 노드·왕복 검출 제한을 유지한다. 시간 예산 조정은 이번 이슈의 범위에서 제외한다.
- `RawTrackDocument`, 공통 모델, 파일 경로·구조는 변경하지 않는다. 재인식 결과는 기존 알고리즘 식별 필드에 `V13-registration1` 및 적용 설정을 기록한다.
- 이동량·작은 변형/일반 탐색 구분은 메모리의 `InitialHeadingFit.registration`과 결과 화면에 표시한다. `CodingKeys`에서 제외해 기존 `correction-diagnostics.json` 구조를 유지한다. 파일만 다시 읽으면 이 실행 중 정보는 복원되지 않는다. 영속 진단·모드 저장이 필요하면 별도 계약 작업으로 진행한다.
- 결과 미리보기는 원본 출발점을 초록 점, 이동한 보정 출발점을 하늘색 원으로 구분한다. 두 점을 임의로 연결하지 않는다.

## 검증

- 회전·이동 후보 생성, 도면 축 이동·실제 축척 적용, 벽으로 분리된 원본 위치에서 평행 이동 후 복도 완주, 보정 선분의 통행 가능성, 수동 기본값의 기존 동작, 진단 JSON 호환성을 테스트한다.
- 녹화 시작 성공 시 모드 확정, 취소 시 미확정, 추적 상태 변화 후 모드 유지, 재인식 실패 후 수동 정책 적용을 테스트한다.
- 제공된 두 원본과 해시가 확인된 장애물 마스크를 사용해 실제 저장소의 최적화 Swift 코드로 재실행한다. 실험 결과의 정점·미해결 구간·상태와 비교한다.
- 앱 내부 문서는 Xcode membership exception에 등록하여 번들 리소스에 포함하지 않는다.
- 시뮬레이터에서는 실제 ARWorldMap 재인식·카메라 이동의 정확도를 검증할 수 없다. 실기기에서 수동 설정, 재인식 성공, 실패 후 수동 전환부터 녹화·보정·업로드까지 확인해야 한다.

### 실행 결과

- MemberApp Debug / iPhone 17 (iOS 27.0) 시뮬레이터 빌드 및 선택한 33개 XCTest 통과(실패 0).
- 테스트 대상: `RouteCorrectionTests`, `RecordingStartLifecycleTests`, `MemberPositioningTests`, `WorldMapPositionCalculatorTests`.
- 저장소의 최적화 Swift 코드를 사용한 두 기록의 재실행에서 실험과 정점 배열·미해결 구간·상태가 모두 일치했다.
  - `7EECD70D…`: `done`, 477개 정점, 130.101939초, 초기 +6° / 우측 0.5m / 작은 변형 탐색.
  - `8CF091FB…`: `partial`, 277개 정점, 123.449787초까지, 초기 +6° / 이동 없음 / 일반 탐색. 나머지는 거리·왕복·벽 조건 불일치.
- 원본·지도 해시 연결과 기존 파일 구조를 유지했다. 새 문서가 앱 번들에 포함되지 않음을 확인했다.
- 실기기 AR·카메라 및 업로드까지의 사용자 흐름은 미실행이다. 실기기에서 추가 확인해야 한다.

재현 명령(시뮬레이터 ID 및 경로는 환경에 맞게 조정):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project CQB/CQB.xcodeproj -scheme MemberApp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:MemberAppTests/RouteCorrectionTests \
  -only-testing:MemberAppTests/RecordingStartLifecycleTests \
  -only-testing:MemberAppTests/MemberPositioningTests \
  -only-testing:MemberAppTests/WorldMapPositionCalculatorTests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```
