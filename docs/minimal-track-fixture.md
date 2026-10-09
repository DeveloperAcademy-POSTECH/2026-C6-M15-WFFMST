# 작은 동선 입출력 샘플 — minimal-v1

관련: [공통 계약 3.6](shared-data-contract.md#동선-최소-입출력-계약-제안), [도면 normal-v1](normal-floorplan-fixture.md), [Issue #14](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST/issues/14)

## 상태와 목적

**사용자 채택 정책의 검토용 합성 샘플 · 팀 승인 전.** 정상·부분 성공·실패·단절을 파일과 수동 기대값으로 표현한다. V13을 실행하거나 실제 이동을 기록한 자료가 아니다. 정상 결과라도 실제 위치 정확도를 증명하지 않는다.

샘플 JSON·바이트 보존 로더에 이어 **공통 좌표/시간 변환, schema 1 동선 문서 검증, 가짜 발행/선택/조회 서비스**의 소비 테스트를 작성했다. 실제 V13 어댑터·앱 연결·Firebase는 없다. 기존 `fixtureFormatVersion`은 **샘플 전용 형식 버전**이며 새 저장 문서의 `schemaVersion`이나 V13 v15와 별개다. 공통 타입/enum과 제한은 [계약 1.5의 검토용 구현안](shared-data-contract.md#동선-schema-1-검토용-구현안)을 따른다. 구현은 팀 승인을 대신하지 않는다.

## 파일과 읽기

위치: [CQBFixtures/Resources/Tracks/minimal-v1](../CQB/Packages/CQBCore/Sources/CQBFixtures/Resources/Tracks/minimal-v1)

| 파일 | 역할 |
| --- | --- |
| normal-raw.json | 유효한 샘플 3개, 시작·직진·회전 |
| tracking-gap-raw.json | 샘플 6개 중 2개는 위치 없음, 같은 원점에서 추적 복구 |
| search-limit-raw.json | 유효한 샘플 4개, 결과는 처음 2개만 제공 |
| insufficient-movement-raw.json | 유효한 샘플 2개, 기록된 이동량 0m |
| solver-snapshots.json | 사람이 정한 보정 후 선택 경로/진단 또는 결과 없음. 보정기 실행 출력이 아님 |
| expected.json | 원본 SHA-256, 식별자, 전달 좌표·시간·상태·연결·미해결 범위·공개/선택 기대값 |

```swift
import CQBFixtures

let raw = try MinimalTrackFixture.data(for: .trackingGapRaw)
let solverSnapshots = try MinimalTrackFixture.data(for: .solverSnapshots)
let expected = try MinimalTrackFixture.data(for: .expectations)
```

로더는 Data를 읽을 뿐 검증/변환/보정을 수행하지 않는다. 패키지 `.copy` 리소스로 원본 바이트를 보존하며 실제 앱 타깃 의존성은 이번에 변경하지 않는다.

## 공통 입력과 손계산

- 도면은 기존 normal-v1의 동일 ID·revision·manifest hash를 재사용한다. PNG/격자를 복제하거나 수정하지 않는다.
- 도면 크기 1000×600px, 격자 2px, 축척 **20px/m**.
- 시작점 정규화 (0.1,0.2) → **(100,120)px**.
- 방향점 정규화 (0.2,0.2) → (200,120)px. 카메라 방향 0rad → 입력 회전 0도.
- AR 원점은 (10,1.5,20)m. 상대 이동 x/y는 AR X/Z에서 원점을 뺀 값이다.
- 예: AR (12,1.5,21)m → 상대 (2,1)m → 도면 **(140,140)px**.
- 기록 시작 offset **0.4초**. 기록 2.0초 → 세션 **2.4초**. 이미 변환한 결과에 offset을 다시 더하지 않는다.
- arTimestamp는 예시 기기 기준 `100 + time`이다. UTC나 서버 시각으로 해석하지 않는다. offset은 이 샘플에서 주입한 값이지 시계 동기화 구현 결과가 아니다.
- 읽기 쉽게 1초 간격을 사용한다. 실제 0.1초 목표 수집 주기나 누락 허용 규칙을 변경하지 않는다.

이 네 샘플은 보정 이동량을 따로 넣지 않은 단순한 선택 경로다. 그래서 도면 투영과 선택 결과가 일치한다. **실제 보정 결과도 항상 원본 투영과 같아야 한다는 뜻이 아니다.** 보정기가 지나야 하는 정답 경로를 새로 정의하지 않는다.

## 네 가지 결과와 수동 기대값

| 사례 | 원본 인덱스별 상대 이동(m) | 세션 시간·도면 좌표 기대값 | 상태 |
| --- | --- | --- | --- |
| normal | 0:(0,0), 1:(1,0), 2:(2,1) | 0.4:(100,120), 1.4:(120,120), 2.4:(140,140), 모두 part 0 | done |
| tracking-gap | 0:(0,0), 1:(1,0), 2:nil, 3:nil, 4:(2,1), 5:(3,1) | 0.4:(100,120), 1.4:(120,120)는 part 0; 4.4:(140,140), 5.4:(160,140)는 part 1 | partial |
| search-limit | 0:(0,0), 1:(1,0), 2:(2,0), 3:(3,0) | 0.4:(100,120), 1.4:(120,120)만 반환, part 0 | partial |
| insufficient-movement | 0:(0,0), 1:(0,0) | 결과 점 없음. (100,120)에 머문 경로를 만들지 않음 | failed + insufficientMovement |

### 정상: 선택된 경로 보존

normal의 `selected = 2`는 **이미 선택된 경로의 전달/복원**을 검증하기 위한 합성 값이다. 나머지 후보는 생략하고 chosen만 기록했다. 전체 V13 `MapMatchResult`로 직접 디코딩할 파일이 아니다. 이 예시는 새 실행 기본 선택을 2번으로 바꾸지 않으며, 기존 선택을 무조건 0번으로 덮어쓰지 않는지 확인한다.

같은 part의 원본 인덱스 0→1, 1→2만 연결한다. 축척을 다시 곱하면 (140,140)이 (2800,2800)으로 바뀌므로 검사에서 거부한다. 점 출처는 모두 `unspecified`다. sampleIndex가 있다는 사실만으로 실제 측정점/높은 정확도로 표시하지 않는다.

### 추적 단절: 100%와 partial이 공존

원본 6개 중 위치가 있는 것은 4개이고, 그 4개에 해당하는 선택 결과가 있다. 이 샘플의 유효 샘플 처리 비율은 **4/4 = 100%**다. 그러나 위치가 없는 인덱스 2·3 때문에 결과 상태는 partial이다. 내부 V13 완료율이나 점수를 수정하지 않는다.

- 0→1, 4→5는 연결 가능. **1→4 연결 금지**.
- solver snapshot은 재개 인덱스 4 하나에만 연결 미확인 사유를 남긴다. 단순 인덱스→시간 변환만으로는 실제 누락 시간을 표현하지 못함을 보여준다.
- 기대하는 미해결 시간은 마지막 유효점과 복구점 사이 **세션 (1.4,4.4)초**다. 끝점 자체에는 위치가 있으므로 양 끝은 제외한다.
- 서로 다른 part를 유지하며 원점은 동일하다. 새 AR 원점 복구나 자동 재정렬을 검증하지 않는다.

### 탐색 제한: 경로가 있으므로 실패로 바꾸지 않음

원본 4개 중 앞의 2개 결과만 있다. 유효 샘플 처리 비율 **2/4 = 50%**, 상태 partial, 진단 searchIncomplete다. 마지막 알려진 점 이후 기록 끝까지 **세션 (1.4,3.4]초**를 미해결로 표시한다. 남은 이동을 임의 보간하지 않는다.

### 이동량 부족: 원본과 실패 사유 보존

원본은 정상 추적이며 두 상대 위치가 같아 이동 합이 0m다. snapshot의 `observedReason`은 이 조건을 확인한 것으로 가정한다. 결과 없음만 보고 원인을 추측하지 않는다. 결과 점 없이 기록 구간 **세션 [0.4,1.4]초**에 경로 생성 불가 사유를 남긴다. 이 샘플을 실제 정지 감지 알고리즘으로 사용하지 않는다.

## 샘플에 한정한 표현·가정

아래는 검토를 위해 명시한 가정이며 추가 공통 정책의 자동 승인이 아니다.

- `bounds`: `()` 양 끝 제외, `(]` 시작 제외/끝 포함, `[]` 양 끝 포함. 새 schema 1 구현안도 이 의미를 사용하고 `[)`를 추가로 지원한다. 팀 승인 전 표현이다.
- `missingSampleIndices`는 원본 위치 없음뿐 아니라 **전달 결과에서 위치를 제공하지 못하는 인덱스**를 뜻한다. 탐색 제한·이동량 부족도 포함한다.
- `validSampleCoverage`는 이 작은 샘플에서 대응 결과가 있는 유효 원본 샘플 비율이다. 실제 V13은 희소 vertices와 보간 samplePoints가 다르므로 운영 코드에서 vertices 수로 완료율을 계산하지 않는다.
- 이 샘플의 ‘사용 가능한 경로’는 같은 part에 서로 다른 위치의 두 점 이상이 있는 경우다. 단일 점·시간 중복·복잡한 범위 겹침·복수 기록 정렬 등 일반 기준을 확정하지 않는다.
- algorithm/version과 실제 실행 설정을 위조하지 않기 위해 `source = hand-authored-selected-candidate-snapshots-not-v13-execution`을 사용한다. schema 1 변환 결과에도 `hand-authored-not-v13-execution`과 `minimal-v1`을 기록한다.
- 원본 JSON의 공백·줄바꿈까지 포함한 SHA-256을 expected에 고정한다. 재인코딩 fingerprint를 원본 파일 hash로 대신하지 않는다.

기대 좌표·시간·연결 쌍·상태는 먼저 손으로 정했다. 원본 hash만 파일 작성 후 계산해 기록했다. 검사 스크립트가 기대값을 자동 갱신하지 않는다.

## 공개·선택 기대값

expected의 publicationExamples는 **수동 입력/기대값 표**다. 파일 자체는 가짜 저장소의 실행 출력이 아니다. 후속으로 `TrackResultRepositoryTests`에서 실제 가짜 서비스에 같은 정책을 적용해 검증했다. `previous-published-result`는 문서용 기호이고, 실행 테스트에서는 동일 recordingID/raw에 새 resultID를 발급해 이전/새 결과를 만든다.

| 상황 | 새 결과 공개 | 선택 기대값 |
| --- | --- | --- |
| 원본 서버 확인 전 | 불가 | 최초 선택 없음 |
| 결과 파일 준비 전 | 불가 | 최초 선택 없음 |
| 원본·결과 준비 완료 + 첫 partial | 경고와 함께 가능 | 해당 partial의 resultID |
| 재보정 failed + 기존 선택 존재 | 실패 진단 공개 여부는 이 샘플에서 판단하지 않음(null) | 기존 선택 유지 |
| 새 정상 결과 + 기존 선택 존재 | 가능 | 자동 교체하지 않고 기존 선택 유지 |
| 재보정 취소 | 새 결과 발행 안 함 | 기존 선택 유지 |

재시도·권한·선택 변경의 원자성은 가짜 서비스 테스트에서 확인한다. 실제 업로드·실패 진단 공개 정책·서버 구현 완료를 뜻하지 않는다. `publishUsable`은 failed 문서를 거부하되, 로컬 문서 validator는 failed 결과와 미해결 범위를 보존한다.

## 공통 코드로 소비하는 단계

[TrackCoordinateTransform / TrackTimeline](../CQB/Packages/CQBCore/Sources/CQBCore/Services/TrackCoordinateTransform.swift)과 [실행 중 사용하는 타입](../CQB/Packages/CQBCore/Sources/CQBCore/Models/TrackCoordinates.swift)을 추가했다. **팀 검토 전 구현안**이며 Codable 저장 DTO가 아니다. 파일 schemaVersion과 기존 샘플 바이트는 바꾸지 않았다.

- `TrackCoordinateTransform`은 검증된 도면의 축척과 시작점·방향·카메라 방향을 받아 AR X/Z 상대 미터를 픽셀로 투영한다. V13 보정·후보 평가·축척 factor 탐색은 수행하지 않는다.
- 시작점은 free 셀이어야 한다. 방향점은 free일 필요는 없지만 V13 `RouteHeading.rotation`과 동일하게 시작점에서 10px 이상 떨어져야 한다. 회전은 같은 식으로 계산하고 0 이상 360도 미만으로 정리한다. 카메라 방향이 없을 때 0이나 firstWalk로 대체하지 않는다.
- 도면 밖으로 투영된 원본 이동은 clamp하지 않는다. 원본 드리프트와 보정 결과 검증은 별개다. 투영기가 이미지·격자 전체를 계속 소유하지 않고 참조·축척·시작점·회전만 보관한다.
- `TrackTimeline.sessionTimeline`은 **이미 보정된 픽셀 좌표를 그대로 유지**하고 기록 시간에 offset만 한 번 더한다. 입력 `RecordingRouteVertex`와 출력 `SessionRouteVertex`를 구분하므로 출력을 그대로 재입력할 수 없다. 숫자를 다시 꺼내 입력 타입으로 재포장하는 오용까지 막는 것은 아니다.
- 이 API의 지원 범위는 기록 시작이 세션 시작 이후인 유한·비음수 offset이다. 사전 녹화·음수 offset·기기 시계 동기화는 구현하지 않는다. 같은 기록 시간은 허용하고 역순 시간·음수 시간·NaN/무한대·오버플로는 거부한다. 정렬이나 재번호로 입력을 고치지 않는다.
- `continuousParts`는 같은 part가 연속된 구간만 묶는다. `[0, 1, 0]`도 세 구간으로 유지한다. **호출당 한 recording/result의 선택 경로만** 전달해야 한다. 다른 결과의 같은 part 번호는 같은 구간이 아니다.
- 원본의 nil/segment를 읽고 누락된 part를 자동 복원하는 기능은 없다. 현재 검사는 올바르게 분리된 선택 경로가 전달·표시 단계에서 다시 연결되지 않음을 증명한다.

[TrackCoordinateTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/TrackCoordinateTests.swift)는 private 샘플 DTO로 네 사례를 읽어 실제 공통 함수의 좌표·시간·연결 쌍을 수동 기대값과 비교한다. 실제 보정에서는 투영과 결과가 달라질 수 있으므로, 투영과 일부러 다른 보정 좌표도 그대로 보존하는 별도 테스트를 둔다.

이 좌표/시간 함수만으로 결과 문서 전체를 검증하지는 않는다. 아래 문서 validator와 가짜 서비스가 추가 검증을 담당한다. V13 출력에서 상태/미해결 범위를 자동으로 생성하는 기능은 아직 없다.

## 저장 모델·가짜 서비스로 소비하는 단계

[TrackContractFixture](../CQB/Packages/CQBCore/Sources/CQBFixtures/TrackContractFixture.swift)는 기존 6개 샘플 파일을 읽어 `RawTrackDocument`/`TrackResultDocument`를 메모리에 만든다. 파일을 덮어쓰지 않는다. 기대 좌표·시간·상태·범위는 기존 수동 기대값에서 가져오며, 원본 hash만 새 schema 1 바이트로 다시 계산한다. 원본 검토 샘플의 hash를 새 파일 hash로 재사용하지 않는다.

```swift
let rawBytes = try TrackContractFixture.rawJSON(.trackingGap)
let raw = try TrackDocumentValidator.raw(rawBytes, floorPlan: validatedMap)
let resultBytes = try TrackContractFixture.resultJSON(.trackingGap)
let result = try TrackDocumentValidator.result(resultBytes, raw: raw, floorPlan: validatedMap)
```

`validatedMap`은 normal-v1을 기존 FloorPlanValidator/CQBImageIO로 검증한 값이다. 이 호출은 알고리즘을 실행하지 않는다.

- [TrackDocumentTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/TrackDocumentTests.swift): 4개 사례의 왕복, 정확한 바이트 hash, 미지원 버전/enum, 잘못된 원점/추적/시간/segment, 도면/원본 불일치, 단절 연결, 희소/생성 점, 결과 상태/미해결 범위, 취소를 검사한다.
- [TrackResultRepositoryTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/TrackResultRepositoryTests.swift): 원본 미확인·staged 비공개·최초 partial 선택·기존 선택 유지·응답 유실/중복 재시도·조건부 선택/과거 재시도·권한 회수·동시 발행·객체 해제를 검사한다.
- `seedSession`/`confirmRaw`는 테스트 조립용으로만 사용한다. 교관/대원 역할의 클라이언트는 같은 actor 저장소를 공유하며 기기 간 통신은 하지 않는다.
- 저장 형식, 최소 usable 기준, 권한, 오류, 지원 한도의 단일 기준은 [공통 계약 1.5](shared-data-contract.md#동선-schema-1-검토용-구현안)다. 기존 문서의 초안 `RawTrack`/`Reconstruction` 전체를 구현한 것은 아니다.

## 검사 방법과 한계

저장소 루트에서 실행한다.

```sh
node scripts/check-minimal-track-fixture.mjs
swift test --package-path CQB/Packages/CQBCore --filter MinimalTrackFixtureTests
swift test --package-path CQB/Packages/CQBCore --filter TrackCoordinateTests
swift test --package-path CQB/Packages/CQBCore --filter 'TrackDocumentTests|TrackResultRepositoryTests'
```

- [읽기 전용 검사](../scripts/check-minimal-track-fixture.mjs): 도면/원본 hash, 4개 사례의 좌표·시간·상태·원본 대응·연결 쌍, 공개 기대값 6개를 확인한다.
- 변형 검사 6개: 축척 중복, offset 중복, 선택 2→0 덮어쓰기, 다른 part 연결, 단절을 done으로 표시, 확인된 실패 사유 제거를 탐지한다.
- [패키지 테스트](../CQB/Packages/CQBCore/Tests/CQBFixturesTests/MinimalTrackFixtureTests.swift): 리소스 6개 접근, 원본 바이트 hash, 합성 표기와 상태 구성을 확인한다.
- 검사 스크립트는 이 샘플 전용이며 실제 공통 validator/상태 분류기/변환기/발행 서비스가 아니다. 범용 처리로 앱에 재사용하지 않는다.
- 결과 점의 free 여부는 확인하지만 공통 선분 충돌 판정 정책이나 알고리즘 정확도를 증명하지 않는다.
- 6명 AAR·영상 조각·실기기 통신·성능·실제 V13 회귀 검증은 포함하지 않는다.

문서·코드·이슈 범위의 기술 대조를 마쳤다. 다음은 schema 1의 제한/필드·권한을 담당자가 검토하고 동일 Fixture 해석을 확인하는 것이다. 팀 승인은 여전히 필요하다. V13 어댑터·실기기 회귀·Firebase 구현은 별도이며 현재 단계만으로 #14를 완료 처리하지 않는다.

### 실행한 검증 (2026-10-10)

- 읽기 전용 샘플 검사: 사례 4개·공개/선택 기대값 6개·변형 검사 6개 통과.
- 패키지 전체: 의미 있는 테스트 98개와 기존 빈 example 1개 통과(CQBFixturesTests 9개 + CQBCoreTests 90개). 공통 변환 13개, 문서 검증 14개, 단절 회귀 6개, Float 회귀 7개, 동선 repository 13개 포함.
- 추가 경고 검사: done/partial의 headingAmbiguous 인코딩·검증 후 좌표/상태 보존, 미지원 경고 거부, 발행 응답 유실 후 재시도·교관 조회의 경고 보존. 원본 합성 리소스 6개를 바꾸지 않고 테스트에서 경고를 주입한다.
- 기존 도면 normal-v1 생성 규칙/바이트 검사 통과, 도면 파일과 hash 유지.
- 동선 문서/가짜 서비스 추가 후 MemberApp/InstructorApp generic iOS Simulator 빌드 통과. 리소스/의존성 및 기존 앱 회귀 빌드이며 화면 주입 검증은 아니다. sandbox의 캐시 접근 제한은 승인 후 재실행했다. MemberApp의 AppIntents 메타데이터 추출 생략 경고는 빌드 실패가 아니다.
- 위 합성 Fixture 검증에는 실제 V13 실행을 포함하지 않는다. 별도로 수행한 실제 자료 재실행은 아래 추가 검증을 참고한다. 실기기·Firebase 서비스·팀 승인 검증은 수행하지 않았으며 가짜 서비스 해제 검사는 장시간 Instruments 측정을 대신하지 않는다.

### 다중 단절 검사 수정 검증 (2026-10-10)

원인은 검사 위치가 **이전 단절의 복구 시각과 현재 선분 시작 시각이 같을 때** 이전 단절에 머무는 것이었다. 예를 들어 raw 단절이 (1.4, 2.4), (3.4, 4.4)이고 결과 선분이 2.4→4.4이면, 첫 단절은 더 이상 겹치지 않지만 두 번째 단절을 검사하지 않고 통과시켰다.

수정은 검증기의 순회 조건만 바꾼다. 길이가 있는 단절의 끝에서 출발하는 선분은 다음 단절을 검사한다. 길이 0인 단절은 기존의 보수적 판정(해당 시각에 닿거나 가로지르는 연결 거부)을 유지한다. 인덱스는 앞으로만 이동하므로 단절 B개·경로점 V개의 해당 교차 검사 비용은 O(B+V)이며 새 배열·비동기 작업·UI 상태를 추가하지 않는다.

아래 기대값은 검증기에서 생성하지 않고 [TrackDiscontinuityTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/TrackDiscontinuityTests.swift)에 시간·구간을 직접 작성했다. **생산 코드를 고치기 전에 같은 테스트를 실행**해 실패를 확인한 뒤 수정 후 재실행했다.

| 완료 기준 / 테스트 | 수정 전 | 수정 후 |
| --- | --- | --- |
| secondBreakIsRejectedForSparseAndDenseVertices: 성긴/촘촘한 경로 모두 두 번째 단절 연결 거부 | 실패: 성긴 경로만 통과 | 통과: 둘 다 disconnectedPath |
| thirdBreakIsNotHiddenBehindTwoSeparatedParts: 앞의 두 구간을 분리해도 세 번째 단절 연결 거부 | 실패: 잘못 통과 | 통과: disconnectedPath |
| repeatedNilTrackingGapsCannotBeJoined: nil 추적 구간을 연결하지 않음 | 통과 | 통과 |
| correctlySeparatedPartsKeepBoundaryVerticesUnchanged: 올바른 part 분리·단절 직전 종료/복구 시각 시작은 허용 | 통과 | 통과: 문서·바이트 그대로 보존 |
| zeroDurationBreakAfterPositiveGapIsStillRejected: 길이 0 단절을 만료된 이전 단절과 함께 건너뛰지 않음 | 실패: 잘못 통과 | 통과: disconnectedPath |
| crossingResultCannotBePublishedOrSelected: 잘못 연결된 결과가 공개·최초 선택되지 않음 | 실패: 공개·선택됨 | 통과: ready=0, pending=0, 선택=nil |

수정 전 6개 중 4개 실패(실패 assertion 6개), 수정 후 6개 모두 통과. 전체 패키지 92개 테스트와 MemberApp/InstructorApp 시뮬레이터 빌드도 통과했다. 재실행 명령:

```sh
swift test --package-path CQB/Packages/CQBCore --filter TrackDiscontinuityTests
swift test --package-path CQB/Packages/CQBCore
```

검증 대상은 공통 validator와 가짜 발행 서비스다. V13 보정 코어·파일 schema·합성 원본 바이트·UI를 바꾸지 않았고, 실제 보정 정확도 개선을 주장하지 않는다. 이 단절 수정에는 Float 허용오차와 페이지 캐시 문제를 포함하지 않았다. Float 검증은 아래 별도 수정으로 다룬다.

### Float 상대좌표 검증 수정 (2026-10-10)

PoC는 ARKit의 Float 위치에서 Float 원점을 뺀 뒤 Double로 승격한다. 기존 validator는 먼저 승격된 Double 위치·원점의 차이만 비교해, 정상 연산의 반올림 차이를 invalidRaw로 오판했다. `Float(40.1) - Float(0.1)` 사례의 두 연산 경로 차이는 약 **1.527369e-6m**로 기존 1e-6m를 넘는다.

기존 Double 경로를 유지하면서 **두 피연산자를 Float로 손실 없이 표현할 수 있을 때만 실제 Float 뺄셈 결과**도 검사한다. 각 경로의 잔여 허용오차는 1e-6m 그대로다. 정상 Float 상대좌표를 다시 계산해 덮어쓰지 않으며, 좌표 크기에 비례해 임의의 값까지 수용하는 범위도 만들지 않는다. 전체 기준과 생산자 연결 방법은 [공통 계약 1.5](shared-data-contract.md#동선-schema-1-검토용-구현안)를 따른다.

[TrackFloatPrecisionTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/TrackFloatPrecisionTests.swift)의 **동일 테스트 7개를 생산 코드 수정 전·후 실행**했다.

| 완료 기준 / 테스트 | 수정 전 | 수정 후 |
| --- | --- | --- |
| pocFloatSubtractionKeepsOriginalBytesAndCoordinates: PoC 방식의 정상 입력 허용·문서/바이트/hash 보존 | invalidRaw로 실패 | 통과·원본 그대로 |
| floatArithmeticAcrossSignsAndMagnitudesIsAccepted: 부호/크기를 바꾼 42개 조합의 X/Z 검사 | invalidRaw로 실패 | 42개 모두 통과 |
| doubleArithmeticAndExistingAbsoluteToleranceRemainSupported: 일반 Double 연산 및 기존 ±0.5e-6m 입력 유지 | 통과 | 통과 |
| coordinateMismatchIsStillRejectedOnEitherAxis: X 또는 Z를 ±0.00001/±0.001m 바꾼 8개 입력 거부 | 통과 | 모두 거부 |
| largeCoordinatesDoNotPermitArbitraryValuesWithinOneFloatULP: 큰 좌표라도 두 연산에 맞지 않는 1m 변조 거부 | 통과 | 거부 |
| doubleOperandsAreNotSilentlyRoundedToFloat: 일반 Double을 Float로 반올림해야만 맞는 상대좌표 거부 | 통과 | 거부 |
| overflowCannotCreateAnInfiniteTolerance: 유한한 위치/원점의 차이가 overflow인 입력 거부 | 통과 | 거부 |

수정 전 7개 중 2개 실패, 수정 후 7개 모두 통과. 전체 패키지 **99개 테스트**와 MemberApp/InstructorApp 시뮬레이터 빌드 통과. 큰 좌표 사례는 수치 경계 시험이지 ARKit의 해당 거리 정확도나 제품 지원 범위를 뜻하지 않는다. 실제 V13 계산·보정 좌표·schema·합성 리소스·UI는 변경하지 않았다. 페이지 캐시 수정과 장시간 메모리 측정은 포함하지 않는다.

```sh
swift test --package-path CQB/Packages/CQBCore --filter TrackFloatPrecisionTests
swift test --package-path CQB/Packages/CQBCore
```

## 추가 검증: 실제 PoC 실험 회귀 (2026-10-10)

위 minimal-v1 합성 테스트와 별도로 실제 실험을 사용했다. **앱 보정기 이관이나 실기기 실행은 아니다.** 외부 floorplanPoC 소스를 수정 없이 임시 CLI에 컴파일해 기존 입력으로 재실행한다. 사용자 원본 파일과 93MiB 규모 Plans.zip은 저장소/앱 리소스에 복사하지 않았다.

### 재실행

[check-recorded-track-regression.sh](../scripts/check-recorded-track-regression.sh)와 [RecordedTrackRegression.swift](../scripts/RecordedTrackRegression.swift)를 사용한다. macOS/Xcode Swift 도구, Node, unzip과 외부 PoC 소스·실험 파일이 필요하며 일반 패키지/CI 테스트의 필수 의존성으로 추가하지 않았다.

```sh
bash scripts/check-recorded-track-regression.sh \
  /path/to/Plans.zip \
  /path/to/experiment-64424296-6B51-41E5-9F16-41258708EB66.json \
  /path/to/floorplanPoC
```

출력된 `/private/tmp/cqb-recorded-regression.*`에 선택한 revision의 5개 파일, 실행 파일, 파생 JSON과 report.json을 둔다. 원본을 수정하지 않으며 저장된 선택 후보를 새 기대값으로 덮어쓰지 않는다. 보고서에는 원본/지도 5개 파일과 사용한 PoC 소스 14개의 SHA-256을 기록한다. 소스 또는 자료가 바뀌면 이를 함께 비교한다.

스크립트는 현재 **contextAware/standard·단절 없는 완료 실험**만 지원한다. 재실행 2회 모두 현재 선택된 결과와 원본 선택 결과의 점/시간/part가 같고 방향 모호성 경고의 codec 보존도 통과해야 한다. 시간 제한 탐색의 일반 결정성을 보장하지는 않는다. 종료 0은 ‘재실행·결과 codec 전달 보존’의 성공이고, 공통 validator까지 전부 통과했다는 뜻은 아니다. `contractProbeFailure`, `productionDirectionPolicyConforms`, `headingWarningPreserved`, `mappedWarnings`를 반드시 확인한다.

### 확인한 자료와 결과

- 실험 SHA-256: `2dd30e1440c25f5a5628af68685ccee04b9b3ce10d85027ebc26d3b59138257b`.
- 도면 `15E62DD3-1C3D-4055-A270-121FF722B530`, revision `3D1FC605-4D05-4F80-9704-A36EDFFFDC2C`.
- 이미지 픽셀 fingerprint·최종 mask fingerprint·축척·revision 일치. base/편집/외곽 재생도 최종 mask와 일치.
- 원본 1,090샘플, 약 108.917초, 저장된 후보 0번의 표시 경로 270점.
- 동일 설정으로 재실행한 2회 모두 후보 0번의 보정 samplePoints 최대 차이 **0px**, vertices의 좌표·시간·sampleIndex·part 동일. 기존 PoC의 점/선분 검사도 통과했다. 이 검사는 공통 계약의 미확정 선분 충돌 정책을 확정한 것이 아니다.
- 저장된 선택 경로를 공통 결과 JSON으로 인코딩/디코딩했을 때 좌표 차이 **0px**. 시간 offset을 한 번만 적용하고 part/sampleIndex를 보존했다. 축척 중복·offset 중복·part 변경을 주입한 변형 3개를 탐지했다.
- 원본의 initialHeadingSearch.ambiguous=true를 headingAmbiguous 경고로 보존했다. 동일 조건 재실행 2회와 codec 검사 재통과. 원본에 진단이 없으면 정확하다는 의미를 만들어 넣지 않는다.
- 파생 JSON의 session/member/recording/result ID 및 offset 0.4초는 **검증용 주입값**이다. PoC sourceID/experimentID를 운영 ID로 단순 변경한 것이 아니며 실제 세션 시계 동기화를 검증하지 않는다. manuallyReviewed=true/rasterizationVersion=1도 분석용 가정이다. 파생 manifest/동선 JSON은 운영 서버에 발행할 자료가 아니다.

### 실제 자료로 드러난 연결 제약

1. **원본 PNG에 불투명하지 않은 픽셀 184,717개가 있다.** 8bit sRGB지만 현재 공통 입력의 완전 불투명 조건을 만족하지 않아 FloorPlanValidator가 `invalidImage`로 거부한다. 전체 raw/result validator 호출은 이 선행 단계에서 중단됐다. 실제 자료의 전체 호환성까지 확인하려면 검증용 정규화 복사본으로 재검사해야 한다. 이는 선택적 추가 검증이며 #14의 필수 종료 조건은 아니다. 검증기를 완화하거나 원본을 덮어쓰지 않았다.
2. **저장된 방향은 firstWalk다.** 저장 회전 258.400307도, 같은 시작/방향점에서 측정 카메라 기준 회전은 253.252827도다(약 5.15도 차이). 두 입력은 같지 않다. 이번 재실행은 firstWalk를 유지했고, cameraAtStart 전환 결과는 측정하지 않았다.
3. **방향 모호성 경고 누락은 보완했다.** `initialHeadingSearch.ambiguous = true`를 TrackResultWarning.headingAmbiguous로 전달하고 codec·가짜 발행/조회에서 보존한다. status를 partial/failed로 강등하거나 좌표·후보 선택을 바꾸지 않는다. 향후 실제 어댑터도 이 매핑을 적용해야 하며 모든 PoC 진단의 이관이 끝났다는 뜻은 아니다. 알고리즘 버전도 capture format v15로 위조하지 않고 원본 algorithm 식별과 별도 버전 필드 부재를 구분한다.

이 결과는 기존 선택 경로의 **재현성과 값 전달 보존**을 증명한다. 실제 보행 정답 동선·실기기 성능·cameraAtStart 결과 동일성·전체 운영 계약 호환성을 증명하지 않는다. 기존 원본을 수정하거나 V13 알고리즘/공통 validator를 바꾸지 않았다.
