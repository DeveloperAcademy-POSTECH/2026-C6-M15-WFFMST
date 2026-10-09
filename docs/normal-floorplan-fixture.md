# 정상 도면 Fixture — normal-v1

관련: [공통 데이터 계약](shared-data-contract.md), [Issue #14](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST/issues/14)

## 목적과 범위

양쪽 앱 담당자가 **동일한 파일의 좌표·축척·최종 격자·도면 참조를 동일하게 해석하는지** 확인하는 작은 정상 샘플이다. 실제 도면이나 PoC 추출 결과가 아니라 수작업으로 규칙을 정한 합성 도면이다. 이미지와 격자는 좌우·상하 비대칭으로 만들어 반전과 행/열 혼동을 발견하기 쉽게 했다.

최초에는 파일·기대값·샘플 자체 정합성을 정의했고, 현재는 CQBCore 모델/validator와 메모리 가짜 Repository에서 같은 자료를 사용하는 검증까지 추가했다. 이 도면을 재사용하는 [작은 동선 입출력 샘플](minimal-track-fixture.md)은 동선 문서 모델/검증기와 가짜 결과 서비스에서도 소비한다. 실제 Local* 내보내기·앱 화면 연동·V13 보정 어댑터는 아직 구현하지 않았다. 팀의 최종 계약 승인이나 두 기기 통신·자동 추출 정확도를 증명하지 않는다.

## 파일과 사용 방법

위치: [CQBFixtures/Resources/FloorPlans/normal-v1](../CQB/Packages/CQBCore/Sources/CQBFixtures/Resources/FloorPlans/normal-v1)

| 파일 | 역할 |
| --- | --- |
| original.png | 1000×600, sRGB·8bit 불투명 RGBA PNG, 4,841바이트 |
| resolved-mask.bin | 500×300 행 우선 UInt8 격자, 정확히 150,000바이트 |
| navigation-map.json | 공통 도면 v1 메타데이터. compact JSON 뒤 LF 하나도 hash에 포함 |
| reference.json | 도면 UUID·revision UUID·manifest 원본 바이트 hash |
| expected.json | 사람이 정한 기대값·조회 지점·두 세션 예제. 테스트 전용 형식 |

`reference.json`은 외부 도면 참조의 샘플이다. `expected.json`의 최상위 형식과 `sessions`는 테스트용이며 새 서버 문서 schema를 정의하지 않는다. 실제 전달 파일은 PNG·격자·manifest이고 참조는 세션/서비스를 통해 제공한다.

패키지는 폴더를 `.copy`로 포함해 JSON과 이진 바이트를 보존한다. CQBFixtures를 연결한 타깃은 아래 공개 API로 파일을 읽을 수 있다. 현재 MemberApp에는 제품 의존성이 있지만 InstructorApp에는 아직 없으므로, 교관 앱에서 사용하려면 후속 앱 연동 단계에서 CQBFixtures 의존성을 추가해야 한다. 이번 단계에서 Xcode 타깃 설정은 변경하지 않는다.

```swift
import CQBFixtures

let imagePNG = try NormalFloorPlanFixture.data(for: .image)
let manifestJSON = try NormalFloorPlanFixture.data(for: .manifest)
let resolvedMask = try NormalFloorPlanFixture.data(for: .mask)
let referenceJSON = try NormalFloorPlanFixture.data(for: .reference)
let expectedJSON = try NormalFloorPlanFixture.data(for: .expectations)
```

이 API는 Data를 읽기만 한다. 도면의 유효성을 보증하거나 데이터를 재인코딩하지 않는다. CQBCore decoder/validator에서 같은 파일을 입력으로 사용한다.

```swift
import Foundation
import CQBCore
import CQBImageIO

let files = FloorPlanFiles(imagePNG: imagePNG, navigationMapJSON: manifestJSON, resolvedMask: resolvedMask)
let reference = try JSONDecoder().decode(FloorPlanReference.self, from: referenceJSON)
let validator = FloorPlanValidator(imageValidator: PNGFloorPlanImageValidator())
let map = try validator.validate(files: files, reference: reference)
// map.pixelsPerMeter == 20, map.cell(at: ImagePoint(x: 100, y: 120))?.index == 30050
```

Foundation/JSONDecoder를 사용하는 위 예시는 필요한 모듈을 연결한 소비자의 호출 예시다. UI actor 밖에서 실행한다. 실제 앱 타깃에는 CQBImageIO 의존성을 아직 추가하지 않았다. 세션 도면을 읽는 호출자는 validator의 expectedReference에 세션의 고정 참조도 전달한다.

## 이미지와 격자의 정의

![정상 도면 Fixture](../CQB/Packages/CQBCore/Sources/CQBFixtures/Resources/FloorPlans/normal-v1/original.png)

- 왼쪽 위 원점, 오른쪽 +x, 아래쪽 +y.
- 흰색: free. 검정: 실내 장애물. 회색: 실내 외곽 밖으로 blocked.
- 실내 외곽: 픽셀 (20,20) → (980,20) → (980,580) → (20,580).
- 정규화 외곽: x=0.02/0.98, y=1/30 및 29/30. JSON에는 유한 소수로 저장하며 픽셀 환산 검사 허용 오차는 1e-9px다. 이 오차는 Fixture 검사값이지 공통 계약의 일반 오차를 새로 정한 것이 아니다.
- 셀 크기: 2px. 각 셀의 중심으로 실내/외곽을 판정한다.
- 장애물 범위는 아래의 반개구간이다. 경계/모서리의 경로 통과 정책을 정의하는 것이 아니다.

| 영역 | 픽셀 범위 | 격자 column / row | blocked 셀 수 |
| --- | --- | --- | ---: |
| 외곽 밖 | x<20 또는 x≥980 또는 y<20 또는 y≥580 | 실내 480×280셀 이외 | 15,600 |
| 좌상단 장애물 | x=[200,240), y=[80,160) | [100,120) / [40,80) | 800 |
| 오른쪽 벽 상부 | x=[600,610), y=[80,280) | [300,305) / [40,140) | 500 |
| 오른쪽 벽 하부 | x=[600,610), y=[320,520) | [300,305) / [160,260) | 500 |
| 우하단 장애물 | x=[800,860), y=[420,460) | [400,430) / [210,230) | 600 |

벽 사이 통로는 y=[280,320), 높이 40px다. 합계는 **blocked 18,000셀 / free 132,000셀 / 전체 150,000셀**이다.

`extractionAlgorithmVersion = synthetic-normal-v1`은 실제 추출기를 실행하지 않았음을 명시한다. `rasterizationVersion = 2`는 현재 셀 중심·외곽 최종 차단 규칙을 따르는 합성 결과임을 나타내며 PoC 실행 증거가 아니다. `manuallyReviewed = true`는 등록 가능한 최종 파일의 예시값으로 작성했으며 팀 승인이나 실제 현장 검수를 뜻하지 않는다.

## 축척과 수동 기대값

- A: 정규화 (0.1,0.2) = 픽셀 (100,120)
- B: 정규화 (0.3,0.2) = 픽셀 (300,120)
- 실제 거리: 10m
- 두 점 사이 200px / 10m = **20px/m**
- 셀 한 변: 2px / 20px/m = **0.1m**

| 조회점 px | column / row | index | 기대값 | 확인 목적 |
| --- | --- | ---: | --- | --- |
| (100,120) | 50 / 60 | 30050 | free | 계약 문서의 숫자 예시 |
| (220,120) | 110 / 60 | 30110 | blocked | 좌상단 장애물 |
| (120,220) | 60 / 110 | 55060 | free | x/y 뒤바뀜 탐지 |
| (220,480) | 110 / 240 | 120110 | free | 상하 반전 탐지 |
| (604,200) | 302 / 100 | 50302 | blocked | 오른쪽 벽 |
| (604,300) | 302 / 150 | 75302 | free | 벽 사이 통로 |
| (604,340) | 302 / 170 | 85302 | blocked | 통로 아래 벽 |
| (820,440) | 410 / 220 | 110410 | blocked | 우하단 장애물 |
| (10,120) | 5 / 60 | 30005 | blocked | 실내 외곽 밖 |
| (20,20) | 10 / 10 | 5010 | free | 실내 왼쪽 위 |
| (1000,120), (100,600), (-1,120) | 없음 | 없음 | blocked | 이미지 밖: 인덱싱/자동 clamp 금지 |

이 기대값은 바이너리 생성기나 미래의 production 계산 함수로 생성하지 않고 고정했다. 점 판정 예제이며 선분 충돌 검사나 보정 경로 예제가 아니다.

## 고정 식별자와 재사용 예제

- floorPlanID: `11111111-1111-4111-8111-111111111111`
- revisionID: `22222222-2222-4222-8222-222222222222`
- sessionID A: `33333333-3333-4333-8333-333333333333`
- sessionID B: `44444444-4444-4444-8444-444444444444`

`expected.json`의 두 세션은 동일한 `reference.json`의 내용을 참조한다. 파일 정합성 테스트는 **두 예제의 참조가 같은지**만 확인한다. 추가한 FloorPlanRepositoryTests에서는 가짜 서비스로 별도의 세션 ID를 실제 생성하고 참조 고정·소유/참가 범위를 검사한다. 이 두 검증을 실제 Firebase 인증/보안 검증과 혼동하지 않는다.

| 파일 | SHA-256 |
| --- | --- |
| original.png | `f23f58918733567de53483e0e1ad7147b88eda602d465710a6cba15530aa4b3f` |
| resolved-mask.bin | `31b66b78e4b08d6540cf2db9244977d5016f1394d5b67bc7214aa8534c17cfa4` |
| navigation-map.json | `1546ad93af9a824f1ae9774fa623e02c6f1ec138eba2d050e868976588b5342d` |

## 검증과 재생성

저장소 루트에서 실행한다.

```sh
# 읽기 전용: 생성 규칙과 현재 PNG/격자 바이트 일치 확인
node scripts/generate-normal-floorplan-fixture.mjs

# Bundle.module 접근, 파일 hash, 좌표/축척, 전체 격자, PNG 디코딩/방향 검증
swift test --package-path CQB/Packages/CQBCore --filter CQBFixturesTests
```

생성 소스는 [generate-normal-floorplan-fixture.mjs](../scripts/generate-normal-floorplan-fixture.mjs)다. Node 기본 모듈만 사용하며 기본 실행은 파일을 수정하지 않는다. `--write`는 PNG와 격자를 덮어쓰는 명시적인 재생성 옵션이다. JSON·기대값·hash를 자동 갱신하지 않는다. PNG 압축 바이트는 Node/zlib 버전에 따라 달라질 수 있으므로 재생성만으로 원본을 대체하지 않는다.

파일을 바꾸면 기대값·manifest hash·외부 참조·두 세션 예제를 함께 검토해야 한다. 이미 공유한 revision을 조용히 덮어쓰지 않고 변경된 샘플은 새 버전/식별자로 추가하는 것을 원칙으로 한다.

CQBFixturesTests는 샘플 자체를, CQBCoreTests의 FloorPlanValidationTests는 실제 공개 모델/validator를 검증한다. 테스트에서 손상 파일·잘못된 좌표/축척/외곽/격자·버전·참조 불일치를 만들며, 의미 검증까지 도달하도록 필요한 hash를 다시 계산한다. 실제 Local* 내보내기와 양쪽 앱 화면 표시는 다음 단계다.

```sh
# Core 소비/거부 테스트와 Fixture 정합성 테스트 전체
swift test --package-path CQB/Packages/CQBCore
```

### 실행한 검증 (2026-10-09)

- 바이너리 생성기 읽기 전용 검사: 통과.
- CQBFixturesTests: 실제 검증 6개 통과. 패키지 전체 테스트도 통과했으며 기존 CQBCoreTests의 빈 example 테스트는 계약 검증 근거에 포함하지 않는다.
- InstructorApp / MemberApp: generic iOS Simulator, CODE_SIGNING_ALLOWED=NO 빌드 통과.
- MemberApp 산출물에 Fixture 번들이 포함된 것을 확인했다. InstructorApp 빌드는 기존 동작의 빌드 회귀 확인이며 Fixture 주입/연동 검증은 아니다.
- 생성 PNG의 비대칭 배치를 시각적으로 확인했다. 실제 앱 화면에서의 표시·실기기 실행·메모리 측정·팀원 확인은 수행하지 않았다.

### 공통 코드 소비 검증 추가 (2026-10-09)

- 공개 API만 import한 Core 검증 테스트 19개 통과(일부는 여러 입력으로 매개변수화). 기존 빈 example 테스트 1개와 Fixture 정합성 테스트 6개도 통과했다.
- 정상 Fixture의 13개 조회점, 축척, 원본 바이트 유지, 정확한 hash, 좌표 왕복, 시작점 거부를 확인했다.
- 손상/CRC/잘림/투명 PNG, 이미지 크기 불일치, 필수 필드·UTF-8·1MiB 제한, 미지원 schema/좌표계/격자 인코딩, 참조 불일치, 축척·외곽·격자 오류와 취소를 검증했다.
- 홀수 이미지의 마지막 셀·외곽 선분 위 셀 중심을 확인했다. 경로 선분 통과 여부 검사는 구현하지 않았다.
- CQBImageIO, MemberApp, InstructorApp의 iOS Simulator 빌드 통과. InstructorApp은 아직 Core/Fixture/이미지 어댑터를 연결하지 않아 회귀 빌드만 확인했다.
- 파일 형식·schemaVersion 1·Fixture 원본 바이트/hash는 변경하지 않았다. 공통 모델·이미지 검증 프로토콜·검증 오류 API의 팀 승인과 노션 기록은 남아 있다.

## 메모리 가짜 서비스 사용

공통 API와 실패 처리 기준은 [공통 계약](shared-data-contract.md)의 3.8을 따른다. 아래는 동일 실행 안에서 교관/대원 역할을 조립하는 예시이며, 앱의 PIN 참가 기능이나 기기 간 통신 구현이 아니다. `files`와 `reference`는 앞의 normal-v1 읽기 예제를 사용한다.

```swift
let backend = InMemoryFloorPlanStore(imageValidator: PNGFloorPlanImageValidator())
let instructor = backend.client(authenticatedUID: "fixture-instructor")
let member = backend.client(authenticatedUID: "fixture-member")
// 실패 후 재시도할 때 새 UUID를 만들지 말고 이 요청 전체를 유지한다.
let request = RegisterFloorPlanRequest(requestID: UUID(), name: "훈련장 A",
                                       reference: reference, files: files)
let summary = try await instructor.register(request)
let session = try await instructor.createSession(
    CreateFloorPlanSessionRequest(requestID: UUID(), name: "훈련 1", floorPlan: summary.reference))
// 검증된 참가 상태를 재현하는 테스트 전용 설정. 앱의 join API가 아니다.
try await backend.setParticipants(["fixture-member"], sessionID: session.sessionID)
let memberMap = try await member.loadForSession(session.sessionID, expectedReference: session.floorPlan)
// memberMap.pixelsPerMeter == 20
```

실패 재현은 `await backend.failOnce(at: .afterStagingRegistration)` 또는 `.afterRegistrationCommit` 등으로 설정한다. 전자는 ready 전 비공개 자료를 남기고, 후자는 등록은 완료됐지만 응답이 유실된 상황이다. 동일 등록 요청을 다시 보내면 하나의 도면으로 복구된다. 새 backend는 빈 저장소이며 다른 앱 프로세스와 메모리를 공유하지 않는다.

```sh
swift test --package-path CQB/Packages/CQBCore --filter FloorPlanRepositoryTests
```

### 서비스 검증 추가 (2026-10-10)

- 서비스 테스트 17개 통과. 패키지 전체에서는 의미 있는 테스트 42개와 기존 빈 example 1개가 통과했다.
- 세션 전 등록·두 세션 재사용·소유/참가 범위·참가 해제·미완료 자료 차단을 확인했다.
- 저장 전/중간/성공 후 응답 유실·같은 요청의 재시도·동시 중복/충돌·세션 참조 교체 거부를 확인했다.
- cursor의 소유자 범위·snapshot/재조회·입력 오류·취소·backend 해제를 검증했다. 해제 테스트는 Instruments 장시간 메모리 측정을 대신하지 않는다.
- MemberApp/InstructorApp generic iOS Simulator 빌드 통과. 실제 화면 주입·Local* 내보내기·Firebase 보안 규칙·두 기기 동기화 검증은 아니다.
- 문서·소스의 팀 승인과 노션 기록은 자동 완료 처리하지 않았다.

### 페이지 캐시 수정 검증 (2026-10-10)

문제는 ARC 순환 참조가 아니라 backend가 살아 있는 동안 `list`가 매번 새 cursor와 잔여 목록 배열을 보관하는 누적이었다. 같은 cursor를 재시도해도 이전 캐시가 남았고, 페이지를 넘길 때마다 뒤쪽 목록을 복사해 보관했다.

수정은 `CQBFixtures/InMemoryFloorPlanStore`에 한정한다. 목록 한 벌의 불변 요약 배열을 snapshot으로 보관하고 기존 cursor는 해당 snapshot의 위치를 사용한다. 공개 Core 프로토콜·도면 파일·등록 자료·보정 계산은 변경하지 않는다.

#### 동작 기준

- 같은 cursor·pageSize 재시도는 항목과 nextCursor가 같으며 캐시를 늘리지 않는다. 페이지 크기를 바꾸어도 같은 snapshot의 해당 위치부터 조회한다.
- `cursor: nil`은 새로운 조회다. 다음 페이지가 있으면 snapshot 하나를 만들고, backend 전체에서 최대 **16개**를 생성 순서(FIFO)로 보관한다. 기존 cursor 읽기는 보존 순서를 갱신하지 않는다.
- 캐시는 요약만 보관한다. 이미지·격자나 cursor별 잔여 배열은 보관하지 않으며, FIFO 보조 배열도 살아 있는 snapshot ID만 가진다.
- 퇴출된 cursor는 `invalidCursor`다. 기존 목록을 비우고 `cursor: nil`부터 재조회해야 한다. 서로 다른 snapshot의 페이지를 이어 붙이지 않는다.
- UID/backend 범위, 미완료 등록 비공개, 새 등록 전 snapshot 내용, 마지막 페이지 재시도를 유지한다. 실패·관찰된 취소는 캐시를 생성하거나 퇴출하지 않는다.
- 이 16개는 Fixture 자원 관리 기준이지 운영 서버의 cursor 만료 정책이 아니다. 요약 개수는 보관된 목록 크기에 비례하므로 고정 MiB 메모리 상한을 보장하지 않는다. 등록 도면·재시도 기록의 보존 정책은 별도다.

#### 수정 전·후 증거

동일한 재현 테스트 9개를 실행해 **수정 전 4개 실패 → 수정 후 9개 모두 통과**를 확인했다. 이후 FIFO 재읽기 검사를 보강하고 여러 UID의 전역 상한 테스트 1개를 추가해 **총 10개 모두 통과**했다.

| 합격 기준·시나리오 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 도면 3개, 동일 중간 cursor 100회 재조회: snapshot 1개·같은 nextCursor | snapshot 101개, 요약 102개, nextCursor 100종 | snapshot 1개, 요약 3개, nextCursor 1종 |
| 도면 12개, 페이지 크기 1→2→3→100 순회: 중복·누락 없이 목록 한 벌 | snapshot 3개, 요약 26개 | snapshot 1개, 요약 12개, 항목 순서 일치 |
| 도면 3개, 첫 페이지 100회 새 조회: 상한 유지·오래된 cursor 거부 | snapshot 100개, 요약 200개, 이전 cursor 계속 허용 | snapshot 16개, 요약 48개, 퇴출 cursor `invalidCursor`·새 조회 성공 |
| 동일 cursor 동시 100회: 동일 결과·캐시 증가 없음 | 새 cursor/캐시 누적 | snapshot 1개, 요약 3개, nextCursor 1종 |
| 실패/취소·권한·잘못된 cursor·미완료 등록·snapshot 불변성 | 기존 기본 동작 유지 | 회귀 통과 |
| 캐시가 채워진 상태에서 client/backend 소유 참조 해제 | 해제됨 | weak 참조 nil 확인 |

추가 검사는 서로 다른 두 UID가 각각 20번 새 조회한 후 backend 전체 snapshot 16개·요약 40개를 유지하며 서로의 cursor를 거부하는지 확인한다. 가장 오래된 snapshot을 재조회한 뒤 새 목록을 만들더라도 생성 순서대로 퇴출되는지도 확인한다. 빈 목록·한 페이지 목록은 캐시를 만들지 않는다.

검증 코드: [FloorPlanPageCacheTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/FloorPlanRepositoryTests.swift). 재실행 명령:

```sh
swift test --package-path CQB/Packages/CQBCore --filter FloorPlanPageCacheTests
swift test --package-path CQB/Packages/CQBCore
```

전체 패키지 **109개 테스트**(Core 100개·Fixtures 9개, 기존 빈 example 1개 포함), MemberApp/InstructorApp generic iOS Simulator 빌드 통과. 테스트의 요약 수는 보관 entry 수이며 실제 RAM 측정값은 아니다. Instruments 장시간 측정·실제 앱 화면 연동·Firebase 커서 정책 검증을 대체하지 않는다.

## 담당자 확인

- [ ] 교관 담당: 도면 표시 방향·장애물·외곽·축척 기대값 확인
- [ ] 아이폰 담당: 이 파일 묶음으로 표시·시작점/방향 설정·보정 입력 구성이 가능한지 확인
- [ ] 공통 계약 검토: 파일 형식과 공개 범위 합의, 변경 기록

자동 테스트 통과로 담당자 확인을 대신 체크하지 않는다.
