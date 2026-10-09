# 공통 데이터 계약 (도메인 · 저장 · 모듈)

## 문서 상태와 적용 기준

**검토 중 — 전체 계약 승인 전** (2026-10-10)

기존 v2 양식을 유지하고 최근 합의·구현 내용을 반영한 통합 문서다. 루트 `docs/`에 있다는 사실이 계약 확정을 의미하지 않는다.

- **현재 적용 기준:** 각 항목에 표시한 제품·전달 규칙을 따른다. 일부 정책 합의를 기술 계약 전체의 승인으로 해석하지 않는다.
- **미확정 제안 / 기존 초안:** 담당자 검토 전에는 확정된 구현 기준으로 사용하지 않는다.
- **구현됨:** 소스·테스트 링크로 구현 범위를 확인한다. 현재 도면 파일 모델·검증·정상 Fixture·도면 서비스 프로토콜과 메모리 가짜 구현이 해당하며, **구현 완료는 팀 합의 완료와 별개**다.
- **팀 승인 및 변경 기록:** 팀원 3명 승인과 노션 변경 기록은 미완료다. 완료 여부는 별도로 확인하고 기록한다.
- **후속 범위:** 실제 Firebase·앱 전체 연결·편집 작업본 영속 저장 등은 선언만으로 구현됐다고 판단하지 않는다.

기준 자료: 첨부된 「데이터 계약 v2 (도메인 · 저장 · 모듈) (확정X)」, [공통 아키텍처](architecture.md), [교관 앱 흐름](../CQB/InstructorApp/docs/flows.md).

기존 스펙: [스펙 문서 최종](https://app.notion.com/p/3f201ce28fac8025b24dc24997ec62fc?pvs=21), [v1 초안](https://app.notion.com/p/3f101ce28fac802288bfc06e3a8c5390?pvs=21). 링크는 출처이며 이번 수정에서 외부 문서의 최신 상태를 재검증한 것은 아니다.

현재 작업: [#14 — 도면·동선 공통 계약 확정 및 Fixture 검증](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST/issues/14), `schema/14-floorplan-contract`.

이 문서는 아이폰(A), AAR(B), 교관 준비·서버(C)가 공유하는 **도면·세션·대원·기록·동선·AAR**의 약속이다. 이번 구현이 도면부터 진행됐다는 이유로 문서 전체를 도면 전용 계약으로 축소하지 않는다.

| 부분 | 무엇을 정하나 | 현재 저장소의 위치 |
| --- | --- | --- |
| 1. 도메인 모델 | 앱 사이에 오가는 데이터의 의미·식별·관계 | `CQBCore/Models` |
| 2. 저장 방식 | 소유·권한·공개 상태·Firestore/Storage 변환 | `CQBFirebase` (구현 예정) |
| 3. 모듈 인터페이스 | 파일 형식·검증·좌표·시간·준비·보정·서비스·Fixture | `CQBCore/Services`, `CQBImageIO`, `CQBFixtures` |

위 모듈은 모두 `CQB/Packages/CQBCore/Sources/` 아래에 있다. 기존 초안의 `CQBCore/Firebase`·`CQBCore/Fixtures` 경로는 현재 구조에 맞게 수정했다.

1부의 Swift 예시는 별도 표시가 없으면 설계안이다. 구현된 도면 타입은 소스 링크를 기준으로 읽는다. 과거 전체 초안은 [이력 문서](archive/shared-data-contract-draft-2026-10-09.md)에 보존하며, 충돌하는 세션 종속 도면 경로·준비 중 도면 교체·firstWalk 선택·아이패드 보정 실행 규칙은 현재 기준으로 사용하지 않는다.

## 0. 공통 규칙

- 이름은 camelCase를 사용한다. 도메인과 저장 DTO의 필드가 다르면 `CQBFirebase`에서 명시적으로 변환한다.
- 도면 ID·revision ID는 UUID이며 공통 도면 JSON writer는 소문자 하이픈 표기를 쓴다. 기존 초안의 대문자 UUID 예시를 도면 writer 기준으로 사용하지 않는다. 다른 저장 DTO의 표기 변경/마이그레이션은 서버 담당자 검토 대상이다.
- PIN은 6자리 숫자 String이라는 기존 초안을 유지한다. PIN은 소유자 ID나 도면 ID가 아니다.
- 앱의 시각은 Date, 상대 시각은 초 단위 TimeInterval을 사용하는 기존 안이다. 서버 시각 `...At`과 기기 시각 `...DeviceAt`을 구분한다. 상세 동선 직렬화와 시간 계산은 3.3의 검토 대상이다.
- 도면 px는 정규화 PNG의 왼쪽 위 원점·오른쪽 +x·아래쪽 +y다. 외곽·편집 획의 0...1 정규화 좌표 및 AR 이동의 m와 혼용하지 않는다.
- enum은 기존 초안에서 String rawValue를 사용한다. 단, `unknown` case 선언만으로 Codable의 미지원 값 처리가 자동 구현되지는 않는다. 도면 schema·좌표계·격자 encoding의 미지원 값은 fallback하지 않고 거부한다.
- 문서 제목의 v2 이력, 공통 도면 파일 schemaVersion 1, PoC capture 형식/알고리즘 버전은 별개다.
- hash는 정확한 파일 바이트의 무결성 검사이며 인증/권한 증명이 아니다. 도면의 구체적 규칙은 1.1과 3.1을 따른다.
- 화면·Store는 Firebase 타입이나 저장 경로를 직접 조립하지 않는다.

### 제품 정책과 현재 작업 범위

- 도면은 세션 생성 전에 등록하고 여러 훈련 세션에서 재사용한다.
- 기존 훈련은 당시 도면 revision을 유지한다. MVP에는 등록 도면 수정·삭제 UI가 없다.
- 도면은 **세션 생성 시 고정**한다. 생성 전에는 선택할 수 있지만, 생성 후 다른 도면을 쓰려면 새 세션을 만든다. 준비·훈련·종료 상태에서 기존 참조를 바꾸지 않는다.
- MVP의 한 세션에는 도면 하나, 팀 배정 한 번, 훈련 시작 명령 한 번을 사용한다.
- 별도 회원가입·로그인 UI 없이 Firebase 익명 인증을 사용한다. 등록한 익명 UID가 도면을 소유하고 재사용한다. 대원은 참가한 세션에 연결된 도면만 읽는다.
- 대원의 시작 방향 기준은 **촬영 시작 카메라 방향**이다. 첫 직진 방향으로 대체하지 않는다.
- 아이폰은 AR 이동의 도면 좌표 변환·보정을 수행한다. 아이패드는 같은 도면 위에 결과를 표시하며 축척을 다시 적용하지 않는다.

도면 재사용·당시 버전 유지·훈련 중 변경 금지는 팀 합의로 전달받은 정책이고, 나머지는 추가 대화에서 수락한 기준이다. 기술 계약 전체에 대한 팀 승인 여부와 구분한다.

#### 현재 이슈의 초점

**데이터 흐름을 정의하고 이를 공통 모델·서비스·Fixture로 구현·검증하는 것**에 집중한다. 이미지 해상도·압축률·용량·메모리 최적화는 이번 단계에서 확대하지 않으며 기존 입력 제한은 유지한다.

#14에는 도면뿐 아니라 원본 동선·보정 결과 계약 검토도 포함되어 있다. 도면 전달을 먼저 검증하되, 아이폰/AAR 담당자 검토를 생략하고 이슈 전체를 완료 처리하지 않는다. GitHub Issue의 범위는 이 문서 정리만으로 변경하지 않는다.

실제 앱 화면·Store 전체 연결, Firebase 저장·인증·보안 규칙 구현, 실제 두 기기 통신, 보정 알고리즘 이관, 상세/수정/삭제, 작업본 영속 저장과 디자인 시스템 적용은 현재 이슈의 제외 범위다. 앱 연동은 후속 이슈에서 진행하거나 먼저 이슈 범위를 명시적으로 조정한다.

## 1부. 도메인 모델

Firebase의 Timestamp·DocumentReference·UIKit 이미지를 공통 모델에 넣지 않는다.

관계는 **소유자의 도면 라이브러리 → 확정 revision**, **세션 → 고정 도면 참조 + 대원**, **대원 기록 → 원본 동선·영상·보정 결과**, **AAR → 그 결과와 재생 설정**이다. 도면의 생명주기는 세션보다 먼저 시작하며 여러 세션에서 재사용한다.

기존 MVP 초안에는 별도 Team 모델이 없다. PIN으로 참가한 대원 집합과 한 번의 팀 배정으로 다룬다(P-6). 앱의 팀 표시 데이터와 별개이며 공통 Team 모델을 이번 수정에서 신설하지 않는다.

### 1.1 도면

**상태: 공통 파일 모델·검증, 목록 요약·서비스 프로토콜·메모리 가짜 Repository 구현됨. Firebase와 앱 연결은 미구현. 팀 검토 전 구현안이다.**

| 모델/정보 | 의미 | 적용 상태 |
| --- | --- | --- |
| `ImagePoint`, `NormalizedPoint`, `MapScale` | px / 0...1 좌표 구분, 두 점과 실제 m | 구현됨 |
| `FloorPlanReference` | floorPlanID + revisionID + navigationSHA256 | 구현됨, 세션 ID 없음 |
| `FloorPlanManifest` | 이미지·격자 크기, 축척·외곽·버전·hash·검수 여부 | 구현됨, 3.1의 필수 필드 |
| `NavigationGridDescriptor` | 격자 인코딩·해상도·크기·hash | 구현됨 |
| `FloorPlanFiles` | PNG·manifest 원본 JSON·최종 격자의 Data | 구현됨 |
| `ValidatedFloorPlan` | 전체 파일 검증을 통과한 소비 입력 | 구현됨, 외부 직접 생성 불가 |
| `FloorPlanSummary` | ready 도면의 이름·참조 | 구현됨. ownerUID·공개 상태는 저장소 내부에서 관리하며 manifest와 분리 |

실제 선언: [Models/FloorPlan.swift](../CQB/Packages/CQBCore/Sources/CQBCore/Models/FloorPlan.swift), [ValidatedFloorPlan](../CQB/Packages/CQBCore/Sources/CQBCore/Services/FloorPlanValidator.swift).

기존 `FloorPlan` 하나에 이름·파일 설명·hash를 혼합한 초안을 위 경계로 나눴다. manifest 안에 자기 자신의 navigationSHA256을 넣지 않는다. 이미지·격자 배열은 Firestore 문서에 넣지 않는다.

#### 식별과 무결성

- `floorPlanID`: 재사용하는 도면 UUID.
- `revisionID`: 이미지·최종 격자·축척·외곽이 고정된 버전 UUID. 최초 등록부터 발급한다.
- MVP는 도면당 revision 하나로 시작한다. 내용 변경 시 새 revision을 만들며 확정 파일과 기존 세션 참조는 덮어쓰지 않는다.
- 세션·시작 설정·기록·보정 결과는 동일한 `FloorPlanReference`를 사용한다. 도면 ID만으로 최신 버전을 다시 찾아 대체하지 않는다.
- imageSHA256과 maskSHA256은 각각 저장할 PNG와 격자의 정확한 바이트로 계산한다.
- navigationSHA256은 확정 manifest의 정확한 UTF-8 바이트로 계산하고 **JSON 자신이 아닌 외부 참조**에 둔다.
- 수신자는 원본 JSON 바이트의 hash를 검사한다. decode→재encode 결과로 비교하지 않는다. 키 순서·공백만 달라도 hash는 달라질 수 있다.
- 발행자는 최초 확정한 바이트를 재시도에 재사용한다. hash는 무결성 검증이며 권한 증명이 아니다.

#### 편집 작업본과 확정 도면

- 교관의 base 격자·막기/열기 획·PencilKit 데이터·편집 캐시는 앱 내부 `Local*` 모델이다. 공통 소비자에게 전달하지 않는다.
- 막기/열기는 입력 순서대로 적용하고 나중 획이 우선한다. 붓 지름은 이미지 짧은 변 대비 비율을 사용하며, 외곽 밖 차단을 마지막에 적용한다.
- 등록 시점에 최종 격자·축척·외곽·정규화 PNG를 공통 형식으로 내보낸다. 자동 추출은 초안이므로 사용자 검수 결과를 사용한다.
- 기존 `ObstacleEditDraft`·`ObstacleEditStroke`·`FloorPlanDraftStatus`와 draft 서버 경로/자동 복원안은 현재 공통 전달 계약에 포함하지 않는다. 기존 상세안은 이력 문서에 보존했다.
- 작업본 영속화·공동 편집·압력/기울기·draft 자동 삭제·셀별 confidence·보정 후보 전체 저장은 후속 범위다.

### 1.2 세션

**상태:** 세션 생성 시 도면 참조 고정은 현재 기준이다. 아래 전체 Session 선언과 상태 enum은 기존 초안을 갱신한 설계안이며 아직 CQBCore 구현이 아니다.

```swift
/// 세션 진행 단계. 앞에서 뒤로만 진행한다.
public enum SessionStatus: String, Codable {
    case preparing
    case waiting
    case running
    case ended
}

/// 훈련 1회
public struct Session: Codable, Identifiable {
    public let id: UUID
    public var pin: String
    public var name: String
    public var status: SessionStatus
    public var createdAt: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var excludedMemberIDs: [UUID]

    /// 생성 시 선택한 확정 도면. 생성 이후 교체하지 않는다.
    public let floorPlan: FloorPlanReference
}
```

세션 생성은 준비된 도면의 참조를 함께 기록해야 성공이다. 기존 `activeFloorPlanRevisionID?`·`activeFloorPlanDraftID?`를 제거한 이유는 **등록과 세션 생성을 분리하고 생성 순간부터 참조를 고정**하기 위해서다. 준비·훈련·종료 중 도면 교체 메서드를 제공하지 않는다. 새 도면이 필요하면 새 세션을 만든다.

이번 단계에서는 전체 Session 대신 `SessionFloorPlanBinding`과 `FloorPlanSessionCreating`만 구현했다. 메모리 서비스의 세션은 ID·이름·불변 도면 참조만 가지며 PIN·훈련 신호·팀 배정은 구현하지 않는다. 실제 SessionRepository 연동 시 세션과 도면 참조를 한 번에 생성해야 하며, 생성 후 별도 attach/교체 API로 이어 붙이지 않는다.

### 1.3 대원과 준비 상태

**상태:** 시작 방향은 `cameraAtRecordingStart`로 정했다. 나머지 Member·DeviceStatus·StartPose 필드와 AR 정렬 계산은 아이폰/서버 담당자 검토 전의 기존 초안이다. 지도 식별 필드는 현재 `FloorPlanReference`에 맞춰 정리했다.

```swift
public enum DirectionReferenceMode: String, Codable {
    /// 기록 시작 순간 휴대폰 카메라가 향하는 방향
    case cameraAtRecordingStart
    case unknown
}

/// 대원이 도면에 지정한 시작 위치와 방향.
public struct StartPose: Codable, Hashable {
    public var start: ImagePoint
    public var directionPoint: ImagePoint
    public var directionMode: DirectionReferenceMode

    /// AR 평면 벡터를 이미지 평면으로 변환하는 회전각.
    /// 이미지 오른쪽 0°, 아래쪽 90°이며 V13 rotationDegrees와 같은 의미다.
    public var arToMapRotationDegrees: Double

    /// 촬영 시작 카메라 방향을 저장하는 안. 프레임 안정화 방식은 아이폰 담당자 검토 대상.
    public var cameraDirectionRadians: Double?

    /// 시작점과 방향점을 지정한 도면 revision
    public var floorPlan: FloorPlanReference
}

public struct Member: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var displayName: String
    public var joinedAt: Date

    /// 서버 시계 − 아이폰 시계(초). 아이폰 시각에 더하면 서버 시각이 된다.
    public var clockOffsetToServer: TimeInterval

    /// 아직 지정하지 않았거나 추적 재시작 등으로 무효가 되면 nil.
    public var startPose: StartPose?
}

public struct DeviceStatus: Codable {
    public var memberID: UUID
    public var startPointSet: Bool
    public var trackingReady: Bool
    public var recording: Bool
    public var updatedAt: Date
}
```

기존 V13 초안은 기록 시작 카메라 위치를 원점으로 두는 안이다. `markedDeviceAt`·4×4 `arTransform`의 필요성과 재시작 시 원점 복구 방식은 아이폰 담당자가 검토한다. `unknown`을 `firstWalk`으로 대신 해석하지 않는다.

- **기존 초안의 표시 규칙:** 마커 번호는 저장하지 않는다. `displayName` 가나다순으로 매번 계산한다(K3).
- **준비됨**은 3.5의 `ReadinessRule`로 계산한다(G-1).

### 1.4 기록

**상태: 기존 초안 유지·아이폰/AAR/서버 담당자 검토 필요.** 아래는 구현된 공통 모델이 아니다. 특히 `Recording.id == memberID`는 대원당 기록 하나를 가정한 기존 안이다. 세션당 훈련 한 번이라는 정책만으로 재촬영/복수 기록 미지원까지 확정하지 않는다. 복수 기록을 지원한다면 recordingID와 2부의 저장 경로를 함께 검토한다.

```swift
public enum EndReason: String, Codable {
    case signal
    case manual
    case error
}

public enum RecordingState: String, Codable {
    case recording
    case uploading
    case done
}

public struct VideoInfo: Codable {
    public var codec: String
    public var width: Int
    public var height: Int
    public var fps: Int
    public var chunkSeconds: TimeInterval
    public var totalChunks: Int?
    public var uploadedChunks: Int
}

public struct VideoChunk: Codable, Identifiable {
    public var index: Int
    public var startSeconds: TimeInterval
    public var durationSeconds: TimeInterval
    public var uploadedAt: Date?
    public var id: Int { index }
}

public enum ReconstructionStatus: String, Codable {
    case pending
    case done
    case partial
    case failed
}
```

**변경: 예시 JSON에만 있던 `algorithmVersion`을 모델에 추가하고, 사용한 원본과 지도 hash 및 탐색 한도 상태를 저장한다.**

```swift
public struct ReconstructionSummary: Codable {
    public var status: ReconstructionStatus

    /// 예: "v13-context-aware-1"
    public var algorithmVersion: String

    /// 예: "contextAware"
    public var engine: String

    /// 입력 재현과 불일치 검사용
    public var sourceRawSHA256: String
    public var floorPlan: FloorPlanReference

    /// 제한 시간 때문에 모든 후보를 검사하지 못했는지
    public var searchIncomplete: Bool

    public var warnings: [ReconstructionWarning]
    public var finishedAt: Date?
}

public struct Recording: Codable, Identifiable {
    public var memberID: UUID
    public var signalReceivedDeviceAt: Date
    public var recordingStartedDeviceAt: Date
    public var recordingEndedDeviceAt: Date?
    public var endReason: EndReason?
    public var rawUploaded: Bool
    public var video: VideoInfo
    public var reconstruction: ReconstructionSummary

    /// 여러 번 재보정한 경우 AAR에서 사용할 결과
    public var selectedReconstructionID: UUID?

    public var state: RecordingState
    public var id: UUID { memberID }
}
```

### 1.5 동선

**상태: 아래 상세 모델·enum·샘플링·파일 버전은 기존 초안이며 아이폰/AAR 담당자 검토 필요.** `schemaVersion: 2`, `captureFormatVersion: 15`를 공통 도면 schemaVersion 1과 혼용하거나 구현 완료로 취급하지 않는다.

```swift
/// 원본 기록의 AR X/Z 평면 이동(m). 이미지 px와 구분한다.
public struct MeterPoint: Codable, Hashable {
    public var x: Double
    public var y: Double
}
```

**변경: 자유 문자열 추적 상태를 enum으로 바꾸고 V13이 실제 입력으로 사용하는 `relativeMeters`를 원본에 저장한다.**

```swift
public enum TrackingState: String, Codable {
    case normal
    case initializing
    case excessiveMotion
    case insufficientFeatures
    case relocalizing
    case notAvailable
    case limited
    case unknown
}

public struct RawSample: Codable {
    /// 기록 시작부터의 초. 단조 증가한다.
    /// 목표 주기는 0.1초지만 실제 간격은 프레임과 기기 부하에 따라 달라질 수 있다.
    public var time: TimeInterval

    /// 기기 부팅 기준 ARKit 프레임 시각. 같은 기기의 영상 동기화에만 사용한다.
    public var arTimestamp: TimeInterval

    /// ARKit 원본 카메라 위치 [x, y, z](m)
    public var arPosition: [Float]

    /// 기록 시작 원점 기준 AR X/Z 평면 이동(m).
    /// trackingState가 normal이 아니면 nil.
    public var relativeMeters: MeterPoint?

    public var trackingState: TrackingState

    /// 추적이 끊겼다가 normal로 돌아올 때 증가한다.
    public var segment: Int
}

public struct RawTrack: Codable {
    public var schemaVersion: Int
    public var sessionID: UUID
    public var memberID: UUID
    public var clockOffsetToServer: TimeInterval
    public var recordingStartedDeviceAt: Date
    public var startPose: StartPose

    /// 기록 당시 잠긴 지도 입력
    public var floorPlan: FloorPlanReference

    /// 기능/알고리즘 계열. 예: "V13"
    public var captureAlgorithmVersion: String

    /// 원본 동선 JSON 형식 버전. 현재 15.
    public var captureFormatVersion: Int

    public var samples: [RawSample]
}
```

**변경: V13이 만든 벽 우회 중간점을 보존하고 단절된 경로를 잘못 직선으로 연결하지 않도록 `TrackPoint` 대신 `RouteVertex`와 `part`를 저장한다.**

```swift
public enum PointQuality: String, Codable {
    /// 정상 추적 샘플과 대응하고 보정 위치가 존재함
    case normal
    /// 보간, 벽 우회 연결 또는 보정 알고리즘이 생성한 점
    case estimated
    /// 원본 추적이 유효하지 않거나 보정 위치가 없음
    case lost
}

public struct RouteVertex: Codable {
    /// 세션 시작 기준 초. 수동 AAR 미세조정은 포함하지 않는다.
    public var t: TimeInterval
    public var x: Double
    public var y: Double

    /// 같은 part 안의 연속 vertex만 선으로 연결한다.
    public var part: Int

    /// 대응 원본 샘플. 우회 중간점이면 nil일 수 있다.
    public var sampleIndex: Int?
    public var quality: PointQuality
}

public enum UnresolvedReason: String, Codable {
    case trackingLost
    case noValidConnection
    case searchLimit
    case invalidStart
    case mapMismatch
    case unknown
}

public struct UnresolvedRange: Codable {
    public var fromSampleIndex: Int
    public var throughSampleIndex: Int
    public var reason: UnresolvedReason
}

public struct Reconstruction: Codable, Identifiable {
    public var schemaVersion: Int
    public let id: UUID
    public var sessionID: UUID
    public var memberID: UUID
    public var summary: ReconstructionSummary

    /// AAR이 실제 경로 선을 그릴 때 사용하는 점. t 순서다.
    public var vertices: [RouteVertex]

    /// 보정되지 않았거나 연결할 수 없는 원본 구간
    public var unresolvedRanges: [UnresolvedRange]
}
```

**AAR은 서로 다른 `part`를 임의로 연결하지 않는다. `lost` 구간에 좌표를 만들어 넣기보다 `unresolvedRanges`로 시간 구간을 표시한다.**

#### 현재 적용하는 역할·좌표 기준

교관이 제공하는 입력은 **같은 revision의 이미지·최종 격자·축척·외곽·참조**다. 아이폰 담당자는 이 자료로 표시·시작 위치/방향 설정·보정 입력 구성이 가능한지 확인한다.

- 시작 방향 기준은 촬영 시작 카메라 방향이다. 도면 위 방향과 AR 좌표계의 방향을 정렬하는 책임은 아이폰에 있다.
- 원본 이동의 m를 도면 px로 변환하고 보정하는 쪽은 아이폰이다. 교관에게는 지도 참조를 포함한 도면 px 결과를 제공한다.
- AAR은 화면 크기·확대율에 맞춘 표시 변환만 적용한다. 축척을 다시 곱하거나 보정을 다시 실행하지 않는다.
- 로컬 보정 계산의 반환과 결과 업로드/교관 조회는 다른 단계다. 함수 반환만으로 다른 기기에 전달되었다고 판단하지 않는다.
- 세션 기준 시간·경로 단절·품질·미해결 구간·원본 식별 정보를 양쪽이 함께 해석해야 한다. 상세 raw/결과 schema와 서비스 API는 아이폰/AAR/서버 담당자 검토 전의 선언을 자동 채택하지 않는다.
- 서로 다른 경로 구간을 직선으로 이어 붙이거나, 추적이 없는 곳에 (0,0) 같은 가짜 위치를 넣지 않는다.
- 세션당 훈련 한 번은 대원 기록 파일 하나와 같은 뜻이 아니다. 일시적 추적 단절·기록 재시작·팀 훈련 재시작을 구분하며 복수 기록 지원 여부를 이 문서에서 새로 확정하지 않는다.
- 추적 단절이 항상 원점 변경을 뜻하지는 않는다. 원점이 바뀐 좌표를 이전 원점 기준으로 해석하지 않으며 복구·재정렬 정책은 아이폰 담당자가 정의한다.

예: 축척 20px/m, 시작점 (100,120), AR→지도 회전 0도일 때 상대 이동 (3,0)m의 **보정 전 변환 위치**는 (160,120)px다. 교관은 결과에 20을 다시 곱하지 않는다. 이는 변환 예시이며 실제 보정 결과나 경로 유효성을 보장하는 예시가 아니다.

도면 데이터의 의미와 역할 분리는 본문 기준을 따른다. 기록 재시작·원점 복구·선분 충돌·상세 결과 모델·raw 업로드 선행 정책은 [이력 문서의 협업 확인 항목](archive/shared-data-contract-draft-2026-10-09.md#협업-확인-항목)에 모아 담당자 검토 자료로만 보존한다.

### 1.6 AAR 설정

**상태: 기존 초안 유지·AAR 담당자 검토 필요.** 수동 시간 미세조정의 포함 여부가 확정되지 않았으며 아래 모델은 아직 구현하지 않았다.

**추가: 기존 Firestore 경로와 시간 변환 설명에 사용됐지만 빠져 있던 모델이다.**

```swift
public struct AARSettings: Codable {
    public var schemaVersion: Int

    /// 대원별 수동 재생 시간 조정값(초)
    public var memberOffsets: [UUID: TimeInterval]

    public var updatedAt: Date
}
```


### 1.7 데이터 흐름과 담당 경계

#### 도면 등록에서 대원 소비까지

| 단계 | 생산/실행 측 | 전달하는 결과 | 소비 측의 행동 |
| --- | --- | --- | --- |
| 이미지 정규화 | 교관 앱 이미지 서비스 | 방향·크기·색상 정규화 이미지 | 추출·편집의 기준으로 사용 |
| 장애물 편집·외곽·축척 확정 | 교관 앱 | 검수한 최종 격자, 외곽, 축척 | 등록 가능 조건 확인 |
| 공통 형식으로 내보내기 | 교관 앱 서비스 | PNG + 격자 + manifest + 도면 참조 | 공통 검증 후 등록 요청 |
| 등록 | 도면 Repository | 검증·공개 완료된 도면 요약 | 목록·세션 생성에서 선택 |
| 세션 생성 | 세션 서비스 | sessionID와 고정 FloorPlanReference | 이후 동일 참조로 조회 |
| 세션 도면 조회 | 대원 앱 → Repository | 같은 revision의 검증된 도면 | 표시·시작점/방향 설정·보정 입력 구성 |
| 보정 결과 소비 | 아이폰 → 결과 저장 서비스 → AAR | 지도 참조를 가진 도면 px 좌표 결과 | 교관은 화면 표시 변환만 적용 |

등록은 세션을 만들지 않는다. 세션 생성 시 도면 전체를 복제하지 않고 확정 revision을 참조한다. 서버 없이 검증할 때도 같은 서비스 경계를 유지한다.

#### 협업 책임

| 담당 | 주도할 정의/구현 | 상대 담당자에게 확인받을 내용 |
| --- | --- | --- |
| 교관 앱 | 정규화 이미지·최종 격자·외곽·축척, 도면 등록/조회 입력 | 이 자료로 대원이 표시·시작점 설정·보정 입력을 구성할 수 있는가 |
| 아이폰 | AR 기록·추적 복구·원점 관리·보정 입출력과 계산 | 도면 규칙과 맞는가, AAR에서 해석 가능한가 |
| AAR | 결과 조회·좌표/시간 표시·단절 구간 표현 | 아이폰의 결과 좌표·시간·품질 의미와 같은가 |
| 서버 | 인증 문맥·소유·접근·공개 상태·저장/재시도 | 공통 서비스의 성공/실패 규칙을 만족하는가 |
| 공통 계약 검토 | 모델·단위·참조·오류·Fixture 해석 | 팀원 3명 승인 및 변경 기록 |

교관 담당자가 상세 raw schema나 AR 복구 정책을 단독 확정하지 않는다. 아이폰 담당자는 제공된 도면 입력의 충분성을 확인하고 동선 계약을 제안한다.

#### 기존 앱과 공통 모듈 연결

- 편집 중에는 기존 `Local*` 모델, base 격자, PencilKit/편집 획과 캐시를 사용한다.
- 등록을 확정하는 경계에서 공통 전달 형식으로 변환하고 검증한다. View에서 파일 인코딩이나 서버 호출을 하지 않는다.
- 등록 이후 소비자는 도면 참조와 서비스 조회 결과를 사용한다.
- 앱 연동 시 실제/가짜 서비스 주입은 `AppContainer`가 담당한다.
- `CQBCore`: 공통 모델·프로토콜·순수 계산/검증. 앱, SwiftUI, Firebase 타입에 의존하지 않는다.
- `CQBFixtures`: 공통 샘플과 가짜 서비스. `CQBFirebase`: 서버 입출력 구현.
- 이미지 디코딩·정규화는 이미지 처리 계층의 책임이다. 공통 모델에 UIKit 이미지를 넣지 않는다.

## 2부. 저장 방식 (Firebase)

도메인과 Firebase DTO의 변환 및 실제 경로 조립은 `CQBFirebase`의 책임이다. **현재 모듈은 설정되지 않은 placeholder이며 아래 경로가 구현됐다는 뜻이 아니다.**

### 2.1 변환 규칙

- Date ↔ Firestore Timestamp, UUID ↔ String, AAR의 UUID 키 dictionary ↔ String 키 Map 변환은 Firebase 어댑터에서 처리한다.
- 기존 서버 시각 대상안은 createdAt·startedAt·endedAt·joinedAt·updatedAt·uploadedAt·finishedAt이다. 해당 서버 이벤트에 serverTimestamp를 쓰는 것과, 파일 안에서 이미 계산한 기기 시각을 덮어쓰는 것은 다르다.
- 도면 manifest에는 날짜·소유 UID·저장 경로가 없다. 해시를 확정한 JSON에 업로드 시각을 삽입하거나 재인코딩하지 않는다.
- 저장 전용 instructorUid(세션)·uid(대원)와 도면 ownerUID의 실제 DTO 필드명은 서버 담당자가 통일한다. 문자열 UID를 모델 입력으로 받았다는 사실만으로 인증됐다고 판단하지 않는다.
- 이미지·격자·동선·영상은 파일 저장소에 둔다. Firestore에는 참조·상태·조회용 메타데이터를 둔다.
- 편집 작업본 자동 저장·복원은 이번 구현에 없다. 기존 edit-draft.json 저장안은 확정 도면 배포의 선행 조건이 아니다.

### 2.2 Firestore 경로

**도면의 논리적 분리는 현재 기준, 다음 물리 경로는 서버 담당자와 확정할 제안이다.** 기존 도면 원본 경로 `sessions/{sessionId}/floorPlanRevisions/{revisionId}`는 재사용 도면의 정본 저장 위치로 채택하지 않는다.

| 대상 | 경로 또는 연결 | 상태/설명 |
| --- | --- | --- |
| 도면 라이브러리 | `floorPlans/{floorPlanId}` | 제안: ownerUID·이름·공개 상태 등. 소유자별 조회/규칙 필요 |
| 확정 revision | `floorPlans/{floorPlanId}/revisions/{revisionId}` | 제안: 확정 참조·파일 위치 등. 세션 생성 전 등록 가능 |
| 세션의 도면 | `sessions/{sessionId}`의 `floorPlan: FloorPlanReference` | 생성 시 고정한다는 의미는 현재 기준. DTO 구현은 예정 |
| PIN | `pins/{pin}` → sessionId·createdAt | 기존 초안 |
| 세션 | `sessions/{sessionId}` → Session·instructorUid | 기존 초안에 도면 참조 변경 반영 |
| 대원 | `sessions/{sessionId}/members/{memberId}` | 기존 초안, Member·uid |
| 준비 상태 | `sessions/{sessionId}/deviceStatus/{memberId}` | 기존 초안, DeviceStatus |
| 기록 | `sessions/{sessionId}/recordings/{memberId}` | 기존 1대원/1기록 가정의 초안; 재촬영 지원 전 재검토 |
| 영상 조각 | `sessions/{sessionId}/recordings/{memberId}/chunks/{index}` | 기존 초안, 0000부터 4자리 |
| 보정 결과 | `sessions/{sessionId}/recordings/{memberId}/reconstructions/{resultId}` | 기존 초안, 결과 요약·파일 참조 |
| AAR 설정 | `sessions/{sessionId}/aar/settings` | 기존 초안 |

도면 루트를 UID 아래에 둘지 위처럼 ownerUID 필드로 관리할지는 실제 보안 규칙·조회 방식과 함께 최종 확정한다. 두 가지 경로를 동시에 사용하는 계약이 아니다. 공통 서비스에는 물리 경로를 노출하지 않아 이 결정이 앱 화면/파일 schema를 바꾸지 않게 한다.

### 2.3 Storage 경로

도면의 세 파일은 **세션과 독립된 동일 revision 위치**에 묶는다. 다음은 2.2의 제안과 짝을 이루는 경로 예시이며 아직 StoragePaths 구현/배포는 없다.

```text
floorPlans/{floorPlanId}/revisions/{revisionId}/original.png
floorPlans/{floorPlanId}/revisions/{revisionId}/resolved-mask.bin
floorPlans/{floorPlanId}/revisions/{revisionId}/navigation-map.json
```

base-mask.bin·edit-draft.json·preview-mask.bin은 이 배포 묶음에 추가하지 않는다. 세션을 만들 때 세 파일을 세션 경로로 복제하지 않는다.

세션에 종속되는 기록·영상은 기존 경로 초안을 유지한다. 복수 기록 결정 전에는 다음 경로로 재촬영 파일을 덮어쓰는 구현을 하지 않는다.

```text
sessions/{sessionId}/members/{memberId}/raw.json
sessions/{sessionId}/members/{memberId}/raw_partial.json
sessions/{sessionId}/members/{memberId}/reconstructions/{resultId}.json
sessions/{sessionId}/members/{memberId}/video/chunk_0000.mp4
```

기존 원본 보존·재보정안은 확정 raw/result를 덮어쓰지 않고 새 계산을 새 result ID로 저장하는 방식이다. 최종 기록 ID·파일 schema/발행 정책은 아이폰/서버 담당자 검토 대상이다. 실제 경로 문자열은 향후 어댑터의 한 곳에서 생성하며 각 앱에서 조립하지 않는다.

### 2.4 동작 규칙

#### 등록 → 재사용 → 참가 세션에서 읽기

1. 교관 인증 문맥에서 세션 ID 없이 도면 파일을 검증하고 라이브러리에 등록한다.
2. 모든 파일·메타데이터 준비가 완료된 revision만 ready로 공개한다.
3. 교관은 자신의 ready 도면 목록에서 참조를 선택해 세션을 생성한다.
4. 세션은 정확한 FloorPlanReference를 보관하며 이후 변경하지 않는다.
5. 대원 조회는 sessionID로 참가 권한과 세션 참조를 확인한 뒤 독립 라이브러리의 해당 파일을 반환한다.

즉 **도면의 저장 위치를 세션에서 분리하는 것**과 **대원이 세션을 통해 권한 있는 도면을 읽는 것**은 양립한다. 대원에게 도면 라이브러리 전체 읽기 권한을 주는 개선이 아니다.

#### 동일 등록 요청과 실패 처리

동일 요청은 **한 번의 도면 등록 의도**를 뜻한다. 저장 버튼 중복 입력뿐 아니라, 서버 저장 후 응답 유실로 성공 여부를 몰라 재시도하는 경우도 포함한다.

- 최초 등록 시 requestID·도면 ID·revision ID와 전송 바이트를 확정한다.
- 동일 인증 문맥에서 같은 요청 ID·같은 이름/참조/파일 내용이면 기존 결과를 반환한다.
- 같은 요청 ID 또는 확정 revision ID로 다른 내용을 덮어쓰려 하면 conflict다.
- 별도 도면을 의도적으로 등록할 때는 새 요청과 도면 ID를 사용한다.
- UI 중복 클릭 차단과 서비스의 중복 처리 방지는 둘 다 필요하다. 시간 초과를 저장 실패 확정으로 해석하지 않는다.

#### 세션·기록 동작 — 기존 초안 유지

아래 주기·상태 완료 판정은 이번 도면 구현으로 검증/확정한 사항이 아니며 해당 담당자 검토가 필요하다.

- PIN은 세션 생성 시 중복 검사 후 생성하고 종료 시 제거한다. 대원은 PIN 단건 조회만 한다(P-8).
- 시작은 status=running과 startedAt을, 종료는 status=ended와 endedAt을 한 번의 상태 변경으로 기록한다. 재연결 시 ended면 기록을 종료한다(K4).
- 준비 상태는 변경 즉시, 변화가 없으면 5초마다 보고한다는 기존 제안이다.
- 영상은 목표 10초 조각별 업로드와 청크 상태 갱신을 사용한다(R-6).
- raw_partial.json은 훈련 중 1분 주기, raw.json은 종료 후 발행하는 기존 안이다(R-6, R-8). 주기와 업로드 선행 정책은 이번에 확정하지 않는다.
- 기록·보정 결과는 사용한 도면 참조를 보존하고 다른 revision으로 대체하지 않는다.
- 재보정은 새 result ID로 만들고 selectedReconstructionID로 선택하는 기존 안이다.
- AAR 전환은 제외되지 않은 대원의 Recording.state가 모두 done일 때라는 기존 안이다. done = rawUploaded + 모든 영상 업로드 완료 + 보정 상태가 pending 아님으로 정의했으나, 업로드 실패/미응답 처리와 함께 검토해야 한다(A-1).

### 2.5 보안 규칙 요약 (S-5)

#### 현재 소유·접근 기준

논리 구조는 **도면 라이브러리 → 확정 revision → 파일**, **세션 → FloorPlanReference**다.

- 인증된 등록 UID를 ownerUID로 사용한다. 호출자가 보내는 UID·도면 ID만으로 소유권을 인정하지 않는다.
- 교관은 자신의 라이브러리를 등록·목록 조회한다. 세션 생성 UID는 선택 도면의 ownerUID와 일치해야 한다.
- 대원은 서버가 확인한 참가 세션과 그 세션의 고정 참조를 기준으로 읽는다.
- 파일과 메타데이터의 검증이 끝난 뒤 ready로 공개한다. 중간 실패 자료는 목록·세션 선택에서 제외한다.
- 실제 저장 경로·Firebase 타입을 공통 프로토콜에 노출하지 않는다. 익명 UID는 사람의 교관 자격이나 기기 고유 ID가 아니다.
- 가짜 서비스의 권한 검증은 실제 Firebase 보안 규칙 검증을 대신하지 않는다.

- 도면 확정 파일의 불변성은 세션 running 이후에만 적용하는 규칙이 아니다. revision 공개 이후 항상 덮어쓰기를 막고, 세션 참조는 생성 이후 항상 고정한다.
- 같은 도면을 두 세션에서 써도 각 대원은 자신이 참가한 세션으로 접근 권한을 얻는다. UUID나 hash를 안다는 이유만으로 파일을 읽게 하지 않는다.
- PIN 참가의 서버 검증 방법·대원 UID 연결·필드별 쓰기 허용·세션 상태 전이 제한은 실제 규칙 구현 시 검증한다. 기존 “교관이면 세션 전체 쓰기 가능” 요약은 확정 참조까지 수정할 수 있다는 뜻이 아니다.
- 읽기 링크나 다운로드 토큰을 사용한다면 배포/재접근 정책도 별도 검토한다. Fixture의 접근 거절 테스트만으로 실제 Storage 파일의 권한이 보장되지는 않는다.
- 익명 계정 재설치/계정 유실·보존/삭제 정책과 draft 권한은 후속 범위다.

## 3부. 모듈 인터페이스

공통 파일 형식·검증·계산·서비스 경계는 CQBCore에, 실제 입출력은 어댑터에 둔다. 아래에서 구현된 API와 초안 API를 구분한다.

### 3.1 파일 형식

#### 전달 파일

| 자료 | 정의 | 이유 |
| --- | --- | --- |
| `original.png` | 방향 보정·크기 정규화·흰 배경 합성이 끝난 sRGB·8bit 단일 정지 PNG | 양쪽 앱의 표시·좌표 기준을 일치시킴 |
| `resolved-mask.bin` | 편집과 외곽 처리가 끝난 격자. 헤더·압축 없는 행 우선 UInt8 배열 | 현재 격자에 직접 대응하고 검증이 단순함 |
| `navigation-map.json` | 이미지/격자 크기·축척·외곽·좌표계·버전·파일 hash를 담은 UTF-8 JSON | 세 파일을 같은 도면으로 해석 |
| `FloorPlanReference` | 도면 ID + revision ID + manifest hash | 세션이 사용한 정확한 파일 조합 식별 |

`original.png`는 업로드 전 원본 파일이 아니라 **정규화 결과**다. base 격자·편집 획·PKDrawing·편집 미리보기는 대원에게 전달하지 않는다. 보정기는 PNG를 재분석하지 않고 최종 격자와 메타데이터를 사용한다.

최종 격자는 사용자가 확정한 장애물 정보이며 실제 공간의 모든 벽·가구를 포함한다고 보장하지 않는다. 격자에서 free라는 뜻과 실제 공간의 안전성은 동일하지 않다.

#### 정규화와 현재 입력 제한

- 입력은 실제 형식을 확인한 PNG/JPEG이며 현재 파일 가져오기 제한 40MiB를 유지한다.
- 방향을 보정하고 종횡비를 유지하며 긴 변을 최대 4,096px로 축소한다. 작은 이미지를 확대하거나 정사각형으로 자르지 않는다.
- 출력의 실제 가로·세로는 각각 1~4,096px다. 회전 보정에 따라 가로·세로가 바뀔 수 있다.
- 이후 축척·격자·시작점·보정 결과의 기준은 정규화된 이미지다. 소비자는 4,096px를 고정 크기로 가정하지 않는다.
- 이미지 최적화와 추가 출력 PNG 용량 상한은 후속 검토로 둔다. 앞서 논의한 80MiB는 현재 코드에 적용된 제한도, 이번 문서에서 성능을 보장하는 기준도 아니다.
- 입력 파일 바이트, 출력 PNG 바이트, 디코딩 픽셀 메모리는 서로 다른 값이다. 기존 제한을 제거하거나 입력을 무제한 허용하지 않는다.

#### 메타데이터 필드

아래 필드는 모두 필수이며 누락·null을 허용하지 않는다. 이름·소유 UID·서버 경로는 계산용 manifest에 추가하지 않고 목록/권한 메타데이터 또는 서비스 문맥에서 관리한다.

| 필드 | 타입/단위·조건 | 생성/사용 목적 |
| --- | --- | --- |
| schemaVersion | 정수 1 | 공통 도면 파일 v1. PoC 버전과 별개 |
| floorPlanID / revisionID | UUID | 외부 참조와 일치해야 함 |
| coordinateSystem | `image-top-left-row-major` | 이미지 왼쪽 위 원점·격자 행 우선 |
| imageWidth / imageHeight | 정수 px, 1~4,096 | 실제 PNG와 일치 |
| imageSHA256 | 소문자 64자리 hex | 정확한 PNG 바이트 검증 |
| scale | a/b: 이미지 px, meters: 실제 m | 축척 계산의 단일 입력 |
| indoorOutline | 정규화 좌표 배열, 유효한 3~512점 | 확정 도면의 실내 외곽. 빈 배열 불가 |
| navigationGrid | 아래 격자 설명 | 이진 파일 해석·검증 |
| extractionAlgorithmVersion | 생성기 버전 문자열 | 생성 이력 식별 |
| rasterizationVersion | 생성기의 정수 버전 | 편집/외곽 격자 생성 이력 식별 |
| manuallyReviewed | Bool, 발행 시 true | 자동 추출 초안과 사용자 검수 결과 구분 |

격자 설명의 필수 필드:

| 필드 | 정의 |
| --- | --- |
| columns / rows | 각각 ceil(imageWidth 또는 imageHeight / cellSizePixels) |
| cellSizePixels | 정수 1~4,096, 현재 생성기 기본값 2 |
| encoding | `uint8-row-major` |
| freeValue / blockedValue | 각각 0 / 1 |
| outsideIsBlocked | true |
| maskSHA256 | 정확한 격자 바이트의 SHA-256 |

#### JSON 작성·읽기 규칙

| 항목 | 기준 | 이유 |
| --- | --- | --- |
| 문서/바이트 | UTF-8, manifest 최대 1MiB | 외곽 최대 512점 등을 수용하면서 비정상 입력 제한 |
| 숫자 | 정수 필드는 정수, 좌표·거리는 유한한 실수. 문자열 숫자·NaN·무한대 거부 | 임의 변환과 계산 오류 방지 |
| UUID 작성 | 소문자 하이픈 포함 표준 문자열 | 직렬화 표현 통일 |
| hash | SHA-256 소문자 64자리 hex | 비교 방식 통일 |
| writer | 공통 writer, 키 정렬, 불필요한 들여쓰기 없음 | 생성 결과 비교가 쉽도록 함 |
| 추가 필드 | 지원 schema 안의 알 수 없는 추가 필드는 무시 | 해석을 바꾸지 않는 부가 정보 수용 |
| 미지원 값 | schema·좌표계·격자 인코딩·장애물 값은 거부 | 의미를 추측해 사용하지 않음 |
| 생성기 버전 | 파일 schema/인코딩을 지원하면 낯선 생성기 버전만으로 거부하지 않음 | 소비자는 확정 격자를 읽으며 재추출하지 않음 |
| PoC 호환 | 기존 PoC 파일을 공통 v1로 자동 인정하지 않음 | 서로 다른 schema/hash 의미를 혼용하지 않음 |

manifest에는 날짜 필드가 없다. raw/결과의 날짜·enum 등 세부 직렬화는 아이폰/AAR 담당자의 동선 schema 검토 대상이며 도면 규칙만으로 자동 확정하지 않는다.

기존 파일 초안 중 도면 이외의 형식은 다음과 같이 유지한다. 구체적인 schema와 지원 여부는 각 담당자의 검토가 필요하다.

| 파일 | 기존 형식안 | 담당 |
| --- | --- | --- |
| chunk_NNNN.mp4 | MP4·HEVC·720p·30fps·목표 10초, preferredTransform으로 회전 정보 보존; 소리 포함 여부 미정 | 아이폰 → AAR |
| raw.json | RawTrack JSON, ISO 8601 밀리초·UTC 날짜 표현안 | 아이폰 → 보정/원본 보관 |
| reconstructions/{resultId}.json | Reconstruction JSON, 결과 ID별 불변 파일 | 아이폰 보정 → AAR |

도면에는 구현된 FloorPlanJSON writer/reader를 사용한다. 기존 초안의 전역 JSONCoding encoder/decoder는 아직 구현되지 않았으며, 동선 날짜·enum 정책을 도면 규칙으로 자동 확정하지 않는다.

### 3.2 예시 파일

도면은 생략 부호가 들어간 임의 JSON 대신 [normal-v1 Fixture와 수동 기대값](normal-floorplan-fixture.md)을 기준 예제로 사용한다.

- [navigation-map.json](../CQB/Packages/CQBCore/Sources/CQBFixtures/Resources/FloorPlans/normal-v1/navigation-map.json): scale·indoorOutline·navigationGrid 중첩 구조를 포함한 실제 manifest.
- [reference.json](../CQB/Packages/CQBCore/Sources/CQBFixtures/Resources/FloorPlans/normal-v1/reference.json): 외부 FloorPlanReference와 manifest hash.
- [expected.json](../CQB/Packages/CQBCore/Sources/CQBFixtures/Resources/FloorPlans/normal-v1/expected.json): 좌표·격자·축척 기대값 및 동일 도면을 쓰는 두 세션의 참조 예시.

기존 v2의 navigation 예시는 scale/outline 누락, 자기 자신의 hash 포함, 격자 필드의 평탄화가 있어 현재 예제로 사용하지 않는다. 기존 raw/reconstruction/edit-draft JSON 예시는 [이력 문서](archive/shared-data-contract-draft-2026-10-09.md)에 보존했다. 담당자 검토 전의 예시를 정상 동선 Fixture로 승격하지 않는다.

### 3.3 시간 변환 (A 보정, B 재생이 같이 씀)

**상태: 기존 시간 변환안·미구현.** 시간 원점, 서버 시계 차이 측정, 수동 보정 부호를 아이폰/AAR 담당자가 함께 확인한다. 실제 공통 API가 이미 있다는 뜻이 아니다.

```swift
public enum SessionClock {
    public static func recordingStartOffset(
        recordingStartedDeviceAt: Date,
        clockOffsetToServer: TimeInterval,
        sessionStartedAt: Date
    ) -> TimeInterval

    public static func sessionTime(
        recordingTime: TimeInterval,
        recordingStartOffset: TimeInterval,
        manualOffset: TimeInterval = 0
    ) -> TimeInterval
}
```

```
recordingStartOffset = recordingStartedDeviceAt + clockOffsetToServer − sessionStartedAt
sessionTime          = recordingStartOffset + recordingTime + manualOffset
```

- **보정(A)은 `manualOffset` 없이 계산해서 `RouteVertex.t`에 넣는다.**
- AAR(B)은 재생할 때 `AARSettings.memberOffsets`를 `manualOffset`으로 더한다. 영상 조각도 같은 함수로 맞춘다.

### 3.4 축척과 장애물 판정

현재 `LocalFloorPlanGeometry`의 기준을 유지한다. 정규화 좌표와 이미지 px는 다른 타입으로 구분하고 내보내는 경계에서 명시적으로 변환한다.

| 데이터 | 단위/방향 |
| --- | --- |
| 외곽·앱 내부 편집 획 | 0...1 정규화 좌표 |
| 공통 축척 A/B·시작점·방향점·보정 결과 | 정규화 PNG 기준 연속 픽셀 좌표 |
| 원본 이동 | 기록 원점 기준 AR X/Z의 m. 높이 AR Y와 구분 |
| 격자 | 정수 column/row, 위쪽 행부터 각 행의 왼쪽에서 오른쪽 |

이미지 원점은 왼쪽 위, 오른쪽 +x, 아래쪽 +y다. SwiftUI pt·화면 확대율·정규화 전 이미지 크기는 저장 좌표가 아니다.

```text
pixelX = normalizedX × imageWidth
pixelY = normalizedY × imageHeight
pixelsPerMeter = hypot(B.x - A.x, B.y - A.y) / meters

columns = ceil(imageWidth / cellSizePixels)
rows    = ceil(imageHeight / cellSizePixels)
column  = floor(pixelX / cellSizePixels)
row     = floor(pixelY / cellSizePixels)
index   = row × columns + column
```

- 축척 기준점은 유효한 이미지 좌표이고 두 점의 간격은 10px 이상이다. 실제 거리는 0 초과 1,000m 이하이며 계산 결과는 유한해야 한다.
- 외곽은 3~512개의 유효한 정규화 점이다. 연속 중복점·겹치는 선분·자기 교차·면적 없는 도형을 거부한다.
- 외곽·축척에는 정규화 경계 1을 허용한다. 격자 조회는 `0 <= x < width`, `0 <= y < height` 밖이면 blocked다. 시작점을 안쪽으로 몰래 clamp하지 않는다.
- 격자는 1셀당 1바이트, 0=free, 1=blocked다. 파일 길이는 정확히 columns×rows이며 크기·곱셈 범위를 검사한 뒤 할당한다.
- 외곽 판정은 셀 중심 기준이다. 외곽 선분 위 중심은 내부이며, 이미지 범위 밖 중심은 blocked다. 홀수 이미지의 마지막 셀에도 적용한다.
- 편집 획을 순서대로 적용한 뒤 외곽 밖을 최종 차단한다. 소비자는 resolved 격자를 재생성하거나 임의 수정하지 않는다.
- 시작점은 범위 내 free 셀이어야 한다. 방향점은 방향 표시용이므로 반드시 free 셀일 필요는 없다.
- **선분이 지나는 셀·경계·모서리의 충돌 판정은 이번에 확정하지 않았다.** 점의 free 판정과 경로 전체 검증은 구분한다. 전체 경로의 장애물 비관통을 현재 검증 완료 조건으로 주장하지 않는다.

예: 1000×600 이미지에서 정규화 A=(0.1,0.2), B=(0.3,0.2)는 픽셀 (100,120), (300,120)이다. 거리가 10m이면 20px/m다. 셀 크기 2px이면 500×300셀이고 (100,120)은 column 50, row 60, index 30050이다.

현재 공통 점 조회는 3.8의 ValidatedFloorPlan API를 사용한다. 기존 ObstacleGrid.canTravel 선분 검사는 보류했으며, 공통 ObstacleGridBuilder와 편집 획 모델 이관도 이번 파일 소비 단계에서 구현하지 않았다. 교관 앱의 편집 미리보기와 확정 격자의 셀 결과는 같아야 하지만 소비 앱이 편집 획을 다시 계산하지는 않는다.

### 3.5 준비 판정 (A 보고, C 표시)

**상태: 기존 ReadinessRule 초안·미구현.** staleAfter=10초는 제안값이며 실제 상태 보고 주기와 함께 결정한다.

```swift
public enum ReadinessRule {
    public static let staleAfter: TimeInterval = 10
    public static func isReady(_ status: DeviceStatus, now: Date) -> Bool
    // 최근 보고 + startPointSet + trackingReady
}
```

startPointSet을 보고하기 전에는 같은 세션 참조의 검증된 도면에서 시작점이 free인지 확인해야 한다. 방향 설정도 필요하며, draft나 preview-mask는 준비 판정의 입력이 아니다. 보고된 Bool만으로 서버의 참조·참가 검증을 대신하지 않는다.

### 3.6 보정 (A 담당, B는 결과 소비)

**현재 역할:** 아이폰이 AR m를 도면 px로 변환하고 보정한다. AAR은 결과를 표시한다. 기존 “K1에 따라 아이패드에서도 호출”은 현재 작업의 기본 실행 정책으로 사용하지 않는다.

아래는 기존 보정 API를 현재 검증된 지도 입력에 맞춰 정리한 **검토용 선언**이다. RawTrack·Reconstruction·경고·실패 정책과 함께 아이폰/AAR 담당자가 검토해야 하며 아직 공통 코드가 아니다.

```swift
public struct ReconstructionInput {
    public var raw: RawTrack
    public var floorPlan: ValidatedFloorPlan
    public var recordingStartOffset: TimeInterval
}

public protocol Reconstructor {
    var algorithmVersion: String { get }
    func reconstruct(_ input: ReconstructionInput) async throws -> Reconstruction
}

public enum ReconstructionWarning: String, Codable {
    case startPoseUncertain
    case trackingLost
    case wallCrossingRemains
    case partialSolve
    case searchIncomplete
    case headingAmbiguous
    case headingAdjustedSignificantly
    case mapRevisionMismatch
    case algorithmVersionMismatch
}
```

- 실제 보정 전 raw·시작 설정·세션이 같은 FloorPlanReference를 사용하는지 확인한다.
- 보정에는 확정 격자·축척·외곽을 사용하며 PNG 재추출이나 편집 획 재생을 요구하지 않는다.
- 보정은 원본 raw를 수정하지 않는다. 결과에는 어떤 원본과 도면을 사용했는지 식별 정보가 필요하다.
- 기존 초안은 입력 오류는 throw, 일부 성공/실패는 summary.status와 unresolvedRanges, 탐색 한도는 searchIncomplete로 표현한다. 시간순·최소 유효 샘플 수 등 상세 입력/성공 기준은 담당자 검토 대상이다.
- 취소는 입력 오류나 정상 부분 성공으로 숨기지 않고 CancellationError로 구분한다.
- 서로 다른 part의 연결 금지와 AAR의 축척 재적용 금지를 지킨다. 전체 선분의 벽 비관통을 이번 검증이 보장하지 않는다.
- 로컬 보정 반환과 결과 업로드·선택·교관 조회는 별도 서비스 단계다. raw 업로드 선행 정책과 발행/선택 API는 아직 제안이다.

### 3.7 가짜 데이터

#### 무엇을 검증하는가

첫 연결 흐름은 **교관 등록 결과 내보내기 → 공통 검증/등록 → 목록 → 세션 참조 고정 → 대원 도면 조회**다.

첫 정상 샘플과 수동 기대값은 [normal-v1 도면 Fixture](normal-floorplan-fixture.md)에 정의했다. 공통 파일 검증에 이어 같은 샘플로 메모리 가짜 Repository의 등록·조회·세션 참조·실패/재시도 테스트까지 구현했다. 실제 Local* 내보내기와 앱 연동은 아직 구현하지 않았다.

| 검증 영역 | 확인할 결과 |
| --- | --- |
| 생산 측 | 실제 로컬 등록 결과를 공통 형식으로 변환하고 다시 읽을 수 있음 |
| 소비 측 | 동일 형식의 비대칭 Fixture를 읽어 좌표·축척·장애물을 같은 의미로 해석 |
| 서비스 | 등록/조회, 중복 요청, 실패/재시도, ready 이전 차단, 소유/참가 범위 |
| 세션 | 같은 도면을 여러 세션에서 사용하되 생성 후 참조 불변 |
| 동선 연결 | 담당자가 확인한 형식으로 입력 구성, 결과 px 표시, 단절 구간 분리 |

고정 Fixture와 기대값은 미리 정한다. 기대값을 검증 대상 함수로만 생성해 같은 오류를 놓치지 않는다. 정상·손상·미지원·참조 불일치 자료를 포함한다.

기존 AAR용 Fixture 계획도 유지한다. 아이폰 담당자가 검토한 형식으로 시작 시각이 있는 세션·대원 6명·대원별 기록/영상 조각·보정 결과를 준비하고, 정상 외 partial·failed·searchIncomplete·추적 단절 사례를 포함한다. 아직 해당 공통 Fixture를 구현한 것은 아니다. 편집 획의 순서·실행 취소·미리보기/확정 일치 검증은 교관 편집 테스트에서 유지하며, 이를 위해 편집 작업본 전체를 대원용 Fixture에 넣을 필요는 없다.

#### 가짜 서비스의 한계

- 같은 `CQBFixtures`를 import해도 iPad의 메모리 변경이 iPhone으로 전달되지는 않는다. 두 앱의 메모리는 별개다.
- 고정 Fixture는 양쪽에서 같은 샘플을 읽는 자료다. 메모리 가짜 서비스는 해당 실행/테스트 안에서만 등록·조회를 제공한다.
- 메모리 등록은 종료 후 복원되지 않는다. 서버 저장·실제 통신·인증 구현 완료처럼 표시하지 않는다.
- 공통 테스트에서 생산→소비 경로를 연결할 수 있지만 이는 실기기 간 동기화 검증과 다르다.
- 실제 보정 알고리즘이 만든 결과가 아닌 고정 결과 샘플은 결과 형식/표시 검증용이다. 알고리즘 정확도 증거로 사용하지 않는다.

raw 업로드 선행 조건을 검토할 때는 가짜 저장소에 검증된 원본의 식별 정보·hash·대원·도면 참조를 사전 등록해 성공/미준비/불일치를 재현할 수 있다. 이는 **조건부 테스트 방법**이지 raw 업로드 선행 정책의 팀 승인이나 실제 업로드 기능 구현을 뜻하지 않는다.

#### 1·2번 Fixture 작업과 세션 종속 경로 개선

| 단계 | 지금 확인된 것 | 아직 확인하지 못한 것 |
| --- | --- | --- |
| 1. 정상 도면과 기대값 | 세션 ID 없는 공통 도면 묶음, 동일 참조를 쓰는 두 세션의 정적 예시 | 라이브러리 저장·세션 생성·참조 변경 거절 |
| 2. 공통 모델과 파일 소비 | 파일만으로 지도 검증, expectedReference 불일치 거절, 좌표·축척 해석 | 서버가 준 참조의 신뢰성, 소유/참가 권한, 실제 저장 경로 |
| 3. 메모리 가짜 서비스 | 독립 라이브러리 등록→목록→두 세션 생성→참가 대원 조회, 중복·실패/재시도·권한·참조 불변 검증 | Firebase 경로·규칙·업로드·실기기 동기화는 별도 |

**판단:** 1·2번은 세션 ID 없는 데이터 형식과 소비 검증이다. 이후 추가한 InMemoryFloorPlanStore가 세션과 독립된 도면 저장과 접근 경계를 검증한다. NormalFloorPlanFixture 자체는 여전히 파일 로더이며, 가짜 서비스 테스트가 실제 Firebase 경로 변경을 뜻하지 않는다.

메모리 가짜 서비스에서 검증한 시나리오:

1. 세션 없이 소유자 A가 도면 등록·목록 조회에 성공한다.
2. 같은 참조로 세션 S1/S2를 만들며 도면 파일이 세션별로 복제되지 않는다.
3. 생성된 세션의 도면 교체는 허용하지 않고, 다른 참조를 기대한 조회는 거절한다.
4. A의 도면을 소유자 B가 조회/세션 연결하려는 요청, 미참가 대원의 세션 도면 요청을 거절한다.
5. ready 전 조회를 막고, 중복 등록/응답 유실 후 동일 요청 재시도가 도면을 중복 생성하지 않는다.

이 테스트는 CQBCore의 서비스 계약과 CQBFixtures의 가짜 구현을 통해 진행했다. 소유자/참가자 문맥은 테스트에서 주입하며 실제 Firebase 보안 검증을 대신하지 않는다. 실제 물리 경로 확정·서버 배포는 서버 담당자 합의 후 별도 연동 작업이다.

### 3.8 검증과 저장·조회 서비스

#### 파일 검증 순서

1. 현재 입력 제한과 manifest 바이트 상한을 확인한다.
2. 외부 참조에 대해 manifest 원본 바이트의 hash를 검증한다.
3. JSON schema·필수 필드·숫자·ID·좌표계·격자 인코딩을 검증한다.
4. 이미지·격자 hash, 격자 길이·값·크기 관계를 검증한다.
5. 이미지 처리 계층에서 실제 PNG 디코딩·크기·정규화 조건을 확인한다.
6. 축척·외곽·외곽 밖 차단 규칙을 검증한다.
7. 서비스가 권한·세션 참조·공개 상태를 확인한 결과만 소비자에게 제공한다.

위 순서는 데이터 검증 순서다. 서버는 파일을 내려주기 전에도 접근 권한을 확인해야 한다. 이미지 처리 계층이 확인한 조건을 포함해 검증을 통과하지 않은 객체를 `ValidatedFloorPlan`으로 생성하지 않는다.

#### 행동별 계약

| 행동 | 입력 | 성공 결과 | 실패 시 처리 |
| --- | --- | --- | --- |
| 도면 등록 | 요청 ID·이름·참조·세 파일 | ready 도면 요약 | draft 유지. 동일 요청 재시도, 잘못된 입력/권한은 중단 |
| 목록 조회 | 페이지 크기·불투명 cursor | 권한 있는 ready 요약·다음 cursor | 기존 목록 유지. 오류를 빈 목록으로 숨기지 않음 |
| 교관 도면 조회 | 참조·library 문맥 | 검증된 지도 | 선택 차단. 다른 revision으로 대체하지 않음 |
| 세션 생성 | 요청 ID·이름·참조 | 참조가 고정된 sessionID | 선택 유지. 동일 요청으로 다른 도면을 보내면 conflict |
| 대원 지도 조회 | sessionID와 고정 참조·session 문맥 | 같은 revision의 지도 | 준비 완료 금지. 재시도 가능, 불일치 지속 시 중단 |
| 시작점 설정 | 검증된 지도·좌표 | 유효한 시작점 | blocked/범위 밖이면 재설정. 자동 이동시키지 않음 |

생성 후 도면을 바꾸는 메서드는 제공하지 않는다. 세션 생성은 참조 기록과 함께 성공해야 한다. 취소는 `CancellationError`로 구분하며 빈 결과나 성공으로 숨기지 않는다. 쓰기 취소/시간 초과가 서버 롤백을 보장하지 않으므로 같은 요청으로 결과를 확인할 수 있어야 한다.

#### 구현된 공통 파일 검증 API

다음 파일 검증 API는 패키지에 구현했다. 메모리 Repository가 이를 사용하지만 앱 Store/화면·Firebase는 아직 연결하지 않았다.

| 코드 | 책임 |
| --- | --- |
| [Models/FloorPlan.swift](../CQB/Packages/CQBCore/Sources/CQBCore/Models/FloorPlan.swift) | 좌표·축척·참조·manifest·파일 모델, 파일 검증 오류 |
| [FloorPlanJSON](../CQB/Packages/CQBCore/Sources/CQBCore/Services/FloorPlanJSON.swift) | UTF-8/버전/필수 필드 decode, 정렬된 키·소문자 UUID encode, 정확한 바이트 SHA-256 |
| [FloorPlanGeometry](../CQB/Packages/CQBCore/Sources/CQBCore/Services/FloorPlanGeometry.swift) | 정규화↔px·축척·외곽 규칙 |
| [FloorPlanValidator / ValidatedFloorPlan](../CQB/Packages/CQBCore/Sources/CQBCore/Services/FloorPlanValidator.swift) | 참조·hash·격자·외곽과 이미지 검증 조립, 검증 이후 점 조회 |
| [FloorPlanImageValidating](../CQB/Packages/CQBCore/Sources/CQBCore/Services/FloorPlanImageValidating.swift) | Core가 요구하는 신뢰할 수 있는 이미지 디코더 경계 |
| [CQBImageIO / PNGFloorPlanImageValidator](../CQB/Packages/CQBCore/Sources/CQBImageIO/PNGFloorPlanImageValidator.swift) | PNG 구조/CRC·단일 정지 이미지·실제 디코딩·크기·방향·sRGB/8bit·불투명 검사 |

`CQBCore`는 Foundation/CryptoKit을 사용하며 SwiftUI/Firebase/ImageIO/CoreGraphics를 import하지 않는다. 양쪽 Apple 앱에서 재사용할 Image I/O 검증 구현만 별도 `CQBImageIO` 타깃으로 분리했다. 이 모듈은 이미지 정규화·압축 최적화를 수행하거나 앱 타깃에 자동 연결하지 않는다.

```swift
import CQBCore
import CQBImageIO

let validator = FloorPlanValidator(imageValidator: PNGFloorPlanImageValidator())
// files와 reference는 서비스에서 받은 원본 바이트/참조.
// 세션 경로에서는 expectedReference에 세션이 고정한 참조를 전달한다.
let map = try validator.validate(
    files: files,
    reference: reference,
    expectedReference: sessionFloorPlanReference
)
let scale = map.pixelsPerMeter
let cell = map.cell(at: ImagePoint(x: 100, y: 120))
let blocked = map.isBlocked(at: ImagePoint(x: 220, y: 120))
try map.validateStart(at: ImagePoint(x: 100, y: 120))
```

- raw 모델 생성/JSON decode만으로 검증이 완료되지는 않는다. `ValidatedFloorPlan`은 외부 생성자나 Codable을 제공하지 않으며 전체 validator를 통과해야 생성된다.
- 이미지 검증 구현은 호출자가 주입하는 신뢰 경계다. no-op 가짜 검사기를 앱에 주입하지 않는다. 검증은 인증/권한/ready 확인을 대신하지 않는다.
- `files`는 원본 manifest 바이트도 보존한다. 재시도에 재encode한 바이트를 쓰지 않는다. 공통 writer는 형식 작성 도구이며 파일 전체 validator를 대신하지 않는다.
- `cell(at:)`은 범위 밖/NaN/무한대에 nil, `isBlocked(at:)`는 true를 반환한다. `validateStart`는 잘못된 좌표와 blocked 시작점을 구분해 거부한다.
- 이미지/격자 검사에는 CPU 작업이 있으므로 UI actor 밖에서 호출한다. 취소는 CancellationError로 전달한다.
- 파일 오류는 `FloorPlanValidationError`로 구분한다: manifest/image/grid/scale/outline/coordinate, blockedStart, unsupportedSchema/CoordinateSystem/Encoding, integrityMismatch, referenceMismatch. 서비스의 권한/재시도 오류와 별개다.
- schemaVersion은 1을 유지한다. 새로운 파일 필드는 추가하지 않았으며 정상 Fixture의 원본 바이트와 hash를 바꾸지 않았다.

#### 구현된 도면 서비스 API — 팀 검토 전 구현안

| 코드 | 책임 |
| --- | --- |
| [FloorPlanRepositoryModels](../CQB/Packages/CQBCore/Sources/CQBCore/Models/FloorPlanRepositoryModels.swift) | 등록 요청·ready 요약·페이지·세션 생성 요청·불변 참조 결과·서비스 오류 |
| [FloorPlanRepository / FloorPlanSessionCreating](../CQB/Packages/CQBCore/Sources/CQBCore/Services/FloorPlanRepository.swift) | 인증 문맥에 묶인 등록·목록·소유 도면/세션 도면 조회, 세션 생성 경계 |
| [InMemoryFloorPlanStore](../CQB/Packages/CQBCore/Sources/CQBFixtures/InMemoryFloorPlanStore.swift) | actor 기반 메모리 저장·원자적 공개/참조 고정·요청 중복 처리·실패 주입 |
| [InMemoryFloorPlanClient](../CQB/Packages/CQBCore/Sources/CQBFixtures/InMemoryFloorPlanClient.swift) | 한 UID 문맥에서 공통 프로토콜 호출 |
| [FloorPlanRepositoryTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/FloorPlanRepositoryTests.swift) | 같은 실제 PNG/격자를 사용한 서비스 흐름·동시 요청·실패/재시도·권한·해제 검증 |

- 등록 요청에는 ownerUID를 넣지 않는다. 서비스 생성 시 인증 문맥을 묶고 서버 어댑터는 실제 인증을 확인한다. 가짜 `client(authenticatedUID:)`는 테스트 조립용이며 인증 기능이 아니다.
- `register`, `list`, `loadOwned`, `loadForSession`은 FloorPlanRepository에, `createSession`은 FloorPlanSessionCreating에 둔다. 전체 세션 프로토콜과 연결할 때 PIN·신호 기능을 이 도면 서비스로 가져오지 않는다.
- `loadForSession`은 저장소의 세션 참조·참가 범위를 먼저 확인하고 호출자의 expectedReference와 대조한다. 호출자가 참조를 알고 있다는 사실만으로 접근을 허용하지 않는다. 세션 소유자도 AAR용 조회가 가능하다.
- 메모리 서비스는 검증된 지도 한 벌을 보관하고 세션에는 참조만 저장한다. 캐시된 지도라도 요청마다 접근 권한을 검사한다. 실제 서버 어댑터는 가져온 바이트에 파일 검증을 적용해야 한다.
- 저장 전 실패, 검증 후 staging 상태 실패, 공개 성공 후 응답 유실을 구분해 재현한다. staging은 목록·조회·세션 생성에서 사용할 수 없고 같은 요청으로 재시도한다. 이 staging은 편집 작업본 영속 저장 기능이 아니다.
- 파일 오류는 FloorPlanValidationError, 서비스 오류는 FloorPlanRepositoryError, 취소는 CancellationError로 구분한다. unavailable은 쓰기 성공 여부가 불명확할 수 있으므로 동일 요청으로 재시도한다.

구현을 위해 둔 제한된 기준(팀 검토 대상):

- 요청 ID는 UID와 작업 종류별로 구분한다. 동일 ID의 재시도는 이름·참조·정확한 파일 바이트까지 같아야 한다. 이름은 공백만 있는 값을 거부하고 임의로 정규화하지 않는다.
- MVP 신규 등록만 제공한다. 이미 사용한 floorPlanID/revisionID를 다른 등록 요청에 재사용하면 conflict다. 새 revision 생성·이름 변경은 이 API로 구현하지 않는다.
- 목록 페이지 크기는 1~100이다. 가짜 서비스는 도면 ID 순서의 ready 목록 snapshot을 사용한다. cursor는 해당 UID·backend 실행 안에서만 유효하며 잘못된 cursor는 invalidCursor다. 운영 목록 정렬/만료 정책을 확정한 것은 아니다.
- 취소·실패가 쓰기 롤백을 의미하지 않는다. 파일 검증/공개 전 취소는 ready로 내보내지 않으며, commit 후에는 같은 요청 재시도로 결과를 확인한다.
- pending 자료·재시도 기록·페이지 snapshot은 가짜 backend의 수명 동안 유지한다. backend를 버리면 모두 해제된다. 운영 서버의 보존/정리 기간과 디스크 복원은 미정이다.
- 실패 주입·참가자 설정·저장 개수 조회는 Fixture의 테스트 도구에만 있다. 공통 프로토콜이나 앱의 참가 API로 노출하지 않는다.

파일 schemaVersion 1·Fixture 원본·실제 서버 경로는 바꾸지 않았다. 공통 서비스 타입/오류 추가의 팀 승인과 노션 기록은 남아 있다.

## 스펙과 맞춰 볼 점

- 기존 초안은 훈련 최대 30분을 기준으로 삼았다(원본 약 18,000 샘플·영상 약 180개). 이는 첨부 문서의 기준을 보존한 것이며 이번에 런타임 한도를 검증한 것은 아니다.
- 수동 AAR 시간 미세조정 포함 여부와 영상 소리/마이크 권한은 기존 확인 항목으로 유지한다.
- 기존 SessionStatus에는 별도 “복기 완료”가 없다. UI 종료와 서버 상태 enum 추가는 별도다.
- 촬영 시작 카메라 방향·세션 생성 시 도면 고정은 현재 기준으로 반영했다. firstWalk이나 running 시점 잠금으로 되돌리지 않는다.
- 가구 자동 분류와 물리 공간 전체의 장애물 보장은 제공하지 않는다. 최종 격자는 사용자 검수 결과다.
- 격자 기본 2px를 소비자 고정값으로 쓰지 않는다. manifest의 cellSizePixels를 읽는다.
- 복수 기록·원점 복구·선분 충돌·raw/결과 상세 schema·업로드 선행 정책은 담당자 검토 전이다. 세부 논의는 [협업 확인 항목](archive/shared-data-contract-draft-2026-10-09.md#협업-확인-항목)을 참고한다.
- 도면 물리 경로, 권한 규칙, 등록/세션 서비스 DTO는 2부의 제안과 현재 정책을 서버 담당자와 맞춘다.

## 변경 규칙

- 공통 모델·프로토콜·저장 경로·파일 형식·공통 enum은 별도 계약 이슈/PR에서 팀원 3명 동의와 노션 변경 기록을 남긴다.
- 문서와 코드가 다르면 무조건 한쪽을 확정값으로 삼지 않고 승인 상태·구현 상태를 먼저 확인한다. 승인된 계약과 구현의 차이를 함께 수정한다.
- 파일 의미/호환성을 바꿀 때 schemaVersion과 마이그레이션 영향을 검토한다. 문서 목차 변경만으로 파일 schemaVersion을 올리지 않는다.
- 확정 도면 파일·기존 세션 참조는 덮어쓰지 않는다. 원본/결과의 보존 정책과 재시도는 담당 영역의 확정 계약에 따라 검증한다.

## 적용 상태와 검증 기준

### 문서와 실제 구현의 구분

- 본문은 프로젝트 전체의 도메인·저장·모듈 계약을 다룬다. 사용자가 수락한 도면 전달 규칙과 기존 비도면 초안의 검토 상태를 구분한다.
- 공통 도면 모델·파일 검증·좌표 계산·서비스 프로토콜·메모리 가짜 구현과 normal-v1 소비 테스트를 구현했다. Firebase·앱 연동·동선 모델은 아직 구현하지 않았고 팀 승인을 대신하지 않는다.
- 팀원 3명 승인과 노션 변경 기록은 미완료다. 담당자 확인 없이 보류 항목을 확정값으로 구현하지 않는다.
- 해상도·용량 최적화는 후속 범위이며 이번에 숫자를 추가 조정하거나 성능 보장을 선언하지 않는다.
- #14 완료에는 도면 검증뿐 아니라 이슈에 적힌 동선 담당자 검토·관련 테스트도 필요하다. 이번 문서 정리는 이슈 완료 선언이 아니다.

### 검증 기준

- [ ] 문서와 CQBCore 모델·프로토콜·검증 코드가 일치한다.
- [x] 공통 파일 validator에서 PNG/manifest/격자 및 좌표·축척·외곽·hash·revision을 검증한다. 서비스 권한 검증은 별도다.
- [ ] 20px/m, index 30050 예시와 경계/홀수 크기를 양쪽에서 동일하게 해석한다.
- [x] 메모리 가짜 서비스에서 등록 중복·실패/재시도·미완료 자료 조회 차단을 검증했다. 실제 서버 검증은 별도다.
- [x] 메모리 가짜 서비스에서 같은 도면 재사용과 세션 참조 불변·소유/참가 접근 범위를 검증했다. 실제 보안 규칙 검증은 별도다.
- [ ] 아이폰 담당자가 전달 자료로 입력 구성이 가능함을 확인한다.
- [ ] 동선 담당자 검토 후 확정한 결과 형식으로 시간·단절·축척 중복 적용 방지를 검증한다.
- [x] 현재 구현 범위의 패키지 테스트와 MemberApp/InstructorApp 시뮬레이터 빌드를 확인했다(2026-10-10). 동선 코드 추가 후 재검증이 필요하다.
- [ ] 팀원 3명 동의와 노션 변경 기록을 남긴다.

## 근거와 변경 기록

### 현재 코드 근거

- [로컬 도면 모델](../CQB/InstructorApp/Models/LocalFloorPlan.swift): 교관 편집 정보와 등록 결과. 전체를 전달 모델로 복사하지 않는다.
- [격자·축척 계산](../CQB/InstructorApp/Services/Geometry/LocalFloorPlanGeometry.swift): 좌표 변환, 10px/1000m, 외곽 3~512점, 외곽 최종 적용.
- [이미지 정규화](../CQB/InstructorApp/Services/Import/LocalFloorPlanImportService.swift): PNG/JPEG 40MiB 입력, 방향·크기·sRGB·흰 배경 정규화.
- [이미지 입력 테스트](../Tests/FloorPlanImportChecks.swift): 작은 이미지 유지·회전·다운샘플링 검사. 링크는 이번 문서 작업에서 테스트를 실행했다는 뜻이 아니다.
- [이전 계약/기술 선언 보존본](archive/shared-data-contract-draft-2026-10-09.md): 과거 schema·PoC 대조·동선 선언. 현재 규칙보다 우선하지 않는다.

### 변경 기록

- 2026-10-09: 미커밋 계약 초안을 develop 기반 schema/14-floorplan-contract로 분리했다.
- 2026-10-09: 익명 UID 소유, 촬영 시작 카메라 방향, 세션 생성 시 도면 고정을 반영했다.
- 2026-10-09: 후속 논의를 반영해 파일/JSON/좌표 규칙·중복 저장·담당 책임·Fixture 한계를 협업 기준으로 정리했다. 세션당 팀 배정/훈련 시작 한 번을 명시했다.
- 2026-10-09: 이미지 최적화는 후속 범위로 남기고 기존 제한을 유지했다. 보류한 선분 충돌 규칙과 미검토 동선 선언은 필수 계약에서 분리했다.
- 2026-10-09: 기존 문서 전체를 이력 파일로 보존했다. 이 문서 정리 시점에는 문서 링크 외 앱 코드·Xcode 설정·GitHub Issue를 변경하지 않았다.
- 2026-10-09: CQBCore 도면 모델·파일/좌표 검증과 CQBImageIO 어댑터를 구현했다. 데이터 필드·schemaVersion 1·Fixture 원본은 유지했다. 파일 오류/이미지 검사 프로토콜을 추가했으며 팀 승인·서비스·앱 연동은 여전히 별도다.
- 2026-10-09: 첨부 v2의 도메인·저장·모듈 3부 구성을 복원했다. 세션·대원·기록·동선·AAR 초안은 검토 상태를 표시해 유지하고, 도면 참조·세션 생성 시 고정·모듈 경로·공통 파일 형식은 현재 기준으로 갱신했다.
- 2026-10-09: 도면 정본의 세션 종속 경로를 독립 라이브러리 논리 구조로 교체하고 물리 경로는 서버 검토 제안으로 표시했다. Fixture 1·2의 검증 범위와 다음 가짜 Repository 검증을 구분했다. 이번 수정은 문서만 변경하며 실제 저장 경로·서비스·파일 바이트를 바꾸지 않았다.
- 2026-10-10: 도면 등록·목록·조회·세션 생성 경계의 공통 프로토콜과 메모리 가짜 서비스를 추가했다. ready 이전 차단·응답 유실 후 재시도·동시 중복/충돌·소유/참가 권한·참조 고정을 정상 도면 Fixture로 검증했다. 서비스 테스트 17개 포함 의미 있는 테스트 42개와 기존 빈 예제 1개가 통과했고 양쪽 앱의 시뮬레이터 빌드를 확인했다. 파일 schema/원본·Firebase 실제 경로·앱 주입은 변경하지 않았으며 팀 승인·노션 기록·동선 계약은 남아 있다.
