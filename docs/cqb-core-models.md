# CQB 공유 데이터 계약

## 목적

이 문서는 대원용 iPhone 앱과 교관용 iPad 앱이 Firebase를 통해 주고받는 최소 데이터 계약을 정의한다.

Firebase는 두 기기 사이의 전달 통로로만 사용한다. 한 기기 안에서 생성되고 소비되는 데이터, 화면 상태, 업로드 재시도 상태는 공통 모델이나 Firebase 저장 대상으로 올리지 않는다.

이 계약의 Swift 타입은 `CQB/Packages/CQBCore/Sources/CQBCore/Models`에 정의한다. Firebase 전용 필드, 저장 경로 생성, DTO 변환은 `CQBFirebase`가 담당한다.

## 설계 원칙

1. 다른 기기로 전달해야 하는 데이터만 `CQBCore/Models`에 둔다.
2. 도면은 `FloorPlanReference`, 기록은 `TrackIdentity`로 연결한다.
3. Firestore에는 실시간 상태와 파일 참조 정보만 저장한다.
4. Storage에는 실제 도면, 보정 결과, 영상 파일만 저장한다.
5. 원본 동선은 대원 기기 안에서 보정에 사용하며 Firebase에 업로드하지 않는다.
6. Firebase 인증 UID, 입장 검증용 PIN, 저장 경로는 Core 모델에 포함하지 않는다.
7. 등록한 도면은 수정하거나 덮어쓰지 않는다. 내용이 달라지면 새로운 `floorPlanID`를 생성한다.
8. MVP에서는 하나의 기록에 하나의 보정 결과만 저장하며 재보정과 결과 선택을 지원하지 않는다.

## Firebase에 저장하는 데이터

| 데이터 | 보내는 쪽 → 받는 쪽 | 저장 위치 | 목적 |
| --- | --- | --- | --- |
| `Session` | iPad → iPhone | Firestore | 세션 정보와 시작·종료 상태 전달 |
| `pins/{pin}` | iPad → iPhone | Firestore | PIN으로 세션 검색 |
| `Member` | iPhone → iPad | Firestore | 입장, 준비 상태 및 준비 단계 연결 상태 전달 |
| `Recording` | iPhone → iPad | Firestore | 기록 진행, 기록 단계 연결 상태 및 업로드 완료 여부 전달 |
| 도면 파일 3개 | iPad → iPhone | Storage | 도면 표시와 로컬 동선 보정 |
| 훈련장 스캔 파일 2개 | iPad → iPhone | Storage | 대원 위치 자동 맞추기 (선택) |
| 보정 결과 파일 | iPhone → iPad | Storage | AAR 동선 표시 |
| 영상 조각 | iPhone → iPad | Storage | AAR 영상 재생 |

도면 목록을 저장하는 별도의 `floorPlans/{floorPlanID}` Firestore 문서는 만들지 않는다. 도면 목록은 교관 기기에 로컬로 보관하며, 세션은 `FloorPlanReference`로 Storage의 도면 묶음을 참조한다.

## Firestore 계약

### 경로와 모델

| 경로 | Core 모델 | `CQBFirebase`가 관리하는 값 |
| --- | --- | --- |
| `pins/{pin}` | 없음 | `sessionID` |
| `sessions/{sessionID}` | `Session` | `instructorUid` |
| `sessions/{sessionID}/members/{memberID}` | `Member` | `uid`, 입장 검증용 `pin` |
| `sessions/{sessionID}/recordings/{recordingID}` | `Recording` | 없음 |

Core 모델은 Firebase 문서 경로나 인증 UID를 알지 않는다. Firestore server timestamp의 기록과 Core `Date` 변환도 `CQBFirebase`의 책임이다.

### Session

```swift
public enum SessionStatus: String, Codable, Sendable {
    case preparing
    case waiting
    case running
    case ended
}

public struct Session: Codable, Sendable, Identifiable {
    public let id: UUID
    public let pin: String
    public let name: String
    public let status: SessionStatus
    public let startedAt: Date?
    public let floorPlan: FloorPlanReference
    public let worldMap: WorldMapReference?
}
```

- `pin`은 대원 앱이 세션을 찾고 교관 앱이 초대 코드를 표시하는 값이다.
- `startedAt`은 모든 기록을 비교할 때 사용하는 세션의 서버 기준 시각이다.
- 세션 시작 전에는 `startedAt == nil`이다.
- `floorPlan`은 세션 생성 시 확정하고 세션 도중 변경하지 않는다.
- `worldMap`은 세션이 쓰는 훈련장 스캔이다. 세션 생성 시 확정하고 세션 도중 변경하지 않는다.
- `worldMap`이 있으면 `worldMap.floorPlan == floorPlan`이어야 한다. 다른 도면에서 만든 스캔의 변환을 적용하지 않기 위해서다. Firestore 규칙이 세션 생성 때 거부하고, Core는 `Session.worldMapMatchesFloorPlan`으로 확인한다.
- `worldMap == nil`이면 스캔하지 않은 훈련장이다. 대원은 지금처럼 출발 위치를 직접 정한다. 이 필드가 없는 기존 세션 문서도 `nil`로 읽는다.
- 세션 상태 전이와 권한 검사는 저장소 구현에서 담당한다.

### Member

```swift
public struct Member: Codable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let name: String
    public let isReady: Bool
    public let lastActiveAt: Date
}
```

- `id`는 대원 기기에 저장하고 같은 세션에 재입장할 때 재사용한다.
- `isReady`는 출발점 설정과 추적 준비가 끝났는지 대원 앱이 판단한 결과다.
- `lastActiveAt`은 대원이 마지막 활동을 알린 서버 시각이다.
- 교관 앱은 기록 시작 전 대원의 연결 상태를 판단할 때 `Member.lastActiveAt`을 사용한다.
- 연결 끊김으로 판단하는 제한 시간은 이 데이터 계약에서 정하지 않는다.

### Recording

```swift
public enum RecordingState: String, Codable, Sendable {
    case recording
    case finishing
    case done
    case failed
}

public struct Recording: Codable, Sendable, Identifiable {
    public let identity: TrackIdentity
    public let state: RecordingState
    public let startedAt: Date?
    public let lastActiveAt: Date
    public let videoChunkCount: Int?

    public var id: UUID { identity.recordingID }
}
```

상태의 의미는 다음과 같다.

| 상태 | 의미 |
| --- | --- |
| `recording` | 녹화 중이다. 완성된 영상 조각은 녹화와 동시에 업로드할 수 있다. |
| `finishing` | 녹화를 종료하고 남은 영상 조각과 보정 결과를 업로드하고 있다. |
| `done` | 보정 결과와 모든 영상 조각의 업로드를 완료했다. |
| `failed` | 대원 앱이 업로드 재시도를 포기했다. |

- `lastActiveAt`은 기록 중인 대원이 마지막 활동을 알린 서버 시각이다.
- 교관 앱은 기록 단계의 연결 상태를 판단할 때 `lastActiveAt`을 사용한다.
- `lastActiveAt`의 갱신 주기와 연결 끊김 제한 시간은 저장소·앱 정책에서 정한다.
- `startedAt`은 실제 기록을 시작한 서버 기준 시각이며 서버 시각이 확정되기 전에는 `nil`일 수 있다.
- `Session.startedAt`과 `Recording.startedAt`의 차이로 세션 시작 후 개별 기록이 시작된 시간을 계산한다.
- `videoChunkCount`는 녹화 종료 후 확정되는 전체 영상 조각 수이며 녹화 중에는 `nil`일 수 있다.
- 영상 조각 index는 0부터 시작한다.
- 개별 영상 조각의 업로드 성공 여부와 재시도 상태는 대원 앱 내부에서 관리한다.
- 보정 결과와 모든 영상 조각의 업로드가 성공한 뒤에만 `done`으로 변경한다.
- 영상 조각별 Firestore 문서는 만들지 않는다.

## Storage 계약

### 저장 경로

```text
floorPlans/{floorPlanID}/original.png
floorPlans/{floorPlanID}/resolved-mask.bin
floorPlans/{floorPlanID}/navigation-map.json

worldMaps/{worldMapID}/world-map.arexperience
worldMaps/{worldMapID}/setup.json

sessions/{sessionID}/recordings/{recordingID}/result.json

sessions/{sessionID}/recordings/{recordingID}/video/chunk_0000.mp4
sessions/{sessionID}/recordings/{recordingID}/video/chunk_0001.mp4
...
```

경로 문자열은 앱이나 Core 모델이 직접 조립하지 않는다. `CQBFirebase`가 식별자를 검증하고 실제 경로를 생성한다.

### 도면 파일

| 파일 | Core 모델 | 역할 |
| --- | --- | --- |
| `original.png` | `FloorPlanFiles.imagePNG` | 표시 및 보정에 사용하는 원본 도면 이미지 |
| `resolved-mask.bin` | `FloorPlanFiles.resolvedMask` | 최종 장애물 마스크 |
| `navigation-map.json` | `FloorPlanManifest` | 이미지, 축척, 좌표 및 탐색 격자 설명 |

`FloorPlanManifest`는 `NavigationGridDescriptor`, `MapScale`, `ImagePoint`, `NormalizedPoint`를 사용한다.

`FloorPlanReference`는 다음 값으로 하나의 불변 도면 묶음을 가리킨다.

```swift
public struct FloorPlanReference: Codable, Hashable, Sendable {
    public let floorPlanID: UUID
    public let navigationSHA256: String
}
```

- `revisionID`를 사용하지 않는다.
- Storage 경로에 `revisions/` 계층을 두지 않는다.
- 이미지, 마스크, 축척 또는 매핑 정보가 달라지면 새로운 `floorPlanID`를 생성한다.
- 등록이 끝난 도면 파일은 덮어쓰지 않는다.

### 훈련장 스캔

교관 앱이 훈련장을 ARWorldMap으로 스캔해 올리고, 대원 앱이 받아 자기 위치를 찾는다. 스캔은 도면 파일과 같은 방식으로 저장한다.

| 파일 | Core 모델 | 역할 |
| --- | --- | --- |
| `world-map.arexperience` | `WorldMapFiles.worldMapArchive` | NSKeyedArchiver로 아카이브한 ARWorldMap. `WorldMapSetup.compression`에 따라 LZFSE로 압축할 수 있다 |
| `setup.json` | `WorldMapSetup` | 어떤 도면용인지, 출발 위치, 대응점, AR → 도면 좌표 변환, 스캔 파일 무결성 정보 |

`WorldMapSetup`은 `FloorPlanReference`, `NormalizedPoint`, `ImagePoint`와 `ARPose`, `WorldMapStart`, `WorldMapCorrespondence`, `WorldMapAlignment`, `WorldMapCompression`을 사용한다.

`WorldMapReference`는 다음 값으로 하나의 불변 스캔 묶음을 가리킨다.

```swift
public struct WorldMapReference: Codable, Hashable, Sendable {
    public let worldMapID: UUID
    public let setupSHA256: String
    public let floorPlan: FloorPlanReference
}
```

- `setupSHA256`은 `setup.json` 바이트의 SHA-256이다. `setup.json`의 `worldMapSHA256`이 다시 스캔 파일을 검증한다. 도면의 `navigationSHA256` → `imageSHA256`, `maskSHA256`과 같은 구조다.
- `floorPlan`은 이 스캔의 대응점과 변환을 계산한 도면이다. 세션 문서만 보고 스캔을 받기 전에 도면과 짝이 맞는지 확인할 수 있다.
- 해시는 파일이 깨지지 않았는지만 보장한다. 조합이 맞는지는 `WorldMapSetup.matches(reference)`로 확인한다. `setup.worldMapID`와 `setup.floorPlan`이 참조와 같아야 한다.
- 스캔한 파일은 덮어쓰지 않는다. 현장이 바뀌어 다시 스캔하면 새로운 `worldMapID`를 생성한다.
- 도면 하나에 날짜별 스캔이 여러 개 있을 수 있다. 그래서 도면 파일 묶음과 분리된 경로에 둔다.
- 도면 이미지는 `setup.json`에 넣지 않고 `floorPlan`으로 참조한다.
- `alignment`는 교관 앱이 대응점으로 한 번 계산해 저장한다. 대원 앱은 다시 계산하지 않고 이 값을 그대로 쓴다. 계산 방법을 바꾸면 저장된 대응점으로 다시 계산해 새 스캔 묶음으로 올린다.
- `alignment`는 AR 월드 좌표 `(x, z)`(미터)를 도면 이미지 좌표(픽셀)로 바꾼다. θ = `rotationDegrees`, s = `pixelsPerMeter`일 때 `imageX = translation.x + s(cos θ·x − sin θ·z)`, `imageY = translation.y + s(sin θ·x + cos θ·z)`다. 대원 앱 보정의 `rotationDegrees`, `pixelsPerMeter`와 같은 규칙이다.
- 도면 위 점(`planPoint`, `directionPoint`)은 0~1 비율 좌표(`NormalizedPoint`)다.
- `worldMaps/{worldMapID}/`에는 `world-map.arexperience`(`application/octet-stream`, 50MB 이하)와 `setup.json`(`application/json`, 1MB 이하)만 올릴 수 있다. 다른 Storage 파일의 제한은 20MB 그대로다.

### 동선 보정 결과

`TrackIdentity`는 기록, 결과, 영상을 같은 기록으로 묶는다.

```swift
public struct TrackIdentity: Codable, Hashable, Sendable {
    public let sessionID: UUID
    public let memberID: UUID
    public let recordingID: UUID
}
```

- 보정 결과는 `sessions/{sessionID}/recordings/{recordingID}/result.json`에 저장한다.
- 기록당 하나의 `TrackResultDocument`만 저장한다.
- `resultID`와 `selectedResultID`를 사용하지 않는다.
- 결과 선택과 재보정을 지원하지 않는다.
- `TrackResultDocument.identity`와 Storage 경로의 식별자가 일치해야 한다.
- `sourceRawSHA256`은 대원 기기에서 보정에 사용한 원본 동선의 해시다. 원본 동선 자체를 Firebase에 업로드한다는 의미가 아니다.

### 영상 조각

- 파일명은 0 기반 index를 사용한 `chunk_NNNN.mp4` 형식이다.
- `videoChunkCount == N`이면 기대하는 조각 index는 `0...(N - 1)`이며 각 index를 네 자리로 채워 파일명을 만든다.
- 대원 앱은 조각별 성공 여부를 로컬에서 관리하고 실패한 조각을 재시도한다.
- 교관 앱은 `Recording.state == .done`과 `videoChunkCount`를 사용해 AAR 준비 여부를 확인한다.

#### 소리 트랙

조각 하나에는 영상 트랙 1개와 소리 트랙 0~1개가 들어 있다. 소리는 교관 앱이 총성을 판정하는 데 사용한다.

| 항목 | 값 |
| --- | --- |
| 코덱 | AAC-LC |
| 채널 | 모노 |
| 비트레이트 | 64kbps |
| 샘플레이트 | 입력 장치 값을 그대로 쓴다 |

- 소리 트랙의 0초는 같은 조각 영상 트랙의 0초와 같다. 두 트랙은 기록 내부 시간축을 함께 쓴다.
- 소리 트랙이 없는 조각을 허용한다. 마이크 권한이 없거나 녹음이 시작되지 않은 경우다.
- 조각 중간의 소리 공백을 허용한다. 전화 등으로 녹음이 끊긴 경우다.
- 읽는 쪽은 소리 트랙 유무와 공백을 확인하고, 소리가 없는 구간은 판정하지 않는다.
- 소리 트랙이 없는 기존 기록도 유효하다.
- 20MB 조각 크기 제한은 소리를 포함한 크기다.
- 소리 유무를 나타내는 Firestore 필드는 두지 않는다.

## 데이터 배치 기준

| 데이터 성격 | 타입 정의 위치 | 값을 소유하는 곳 | 예시 |
| --- | --- | --- | --- |
| 한 화면에서만 사용하는 임시 값 | 기본 타입 또는 Feature 내부 | View 상태 | 입력 중인 PIN, 확인창 표시 여부 |
| 한 앱의 여러 화면이 공유하는 상태 | 앱의 `Stores/` | 앱의 Store | 현재 phase, 로딩 상태, 선택한 대원 |
| 한 앱에서만 사용하는 데이터 | 앱의 `Models/` | 앱의 Store | 편집 중인 `LocalFloorPlan` |
| 두 앱과 서버가 주고받는 데이터 | `CQBCore/Models` | 각 앱의 Store | `Session`, `Member`, `Recording` |
| 저장 시에만 필요한 데이터 | `CQBFirebase` | Firebase DTO | `instructorUid`, `uid`, 입장 검증용 `pin` |

## Firebase에 저장하지 않는 데이터

- 보정 전 원본 동선
- 영상 조각별 업로드 성공 여부와 재시도 횟수
- 도면 목록과 편집 중인 도면
- 화면 phase, 로딩 상태, alert 표시 여부
- AAR 화면에서 선택한 대원 등 앱 내부 선택 상태
- Firebase 경로 문자열

## 시간과 연결 상태

현재 합의된 연결 상태 기준은 다음과 같다.

| 단계 | 기준 시각 | 의미 |
| --- | --- | --- |
| 기록 시작 전 | `Member.lastActiveAt` | 대원이 마지막 활동을 알린 서버 시각 |
| 기록 중 및 업로드 중 | `Recording.lastActiveAt` | 대원이 마지막 활동을 알린 서버 시각 |

두 값은 연결 상태를 판단할 근거만 제공한다. 갱신 주기, timeout 값, 백그라운드 상태 처리와 자동 `failed` 전환은 후속 구현 정책에서 정한다.

### 세션 시각과 기록 시각 연결

- `Session.startedAt`은 세션의 서버 기준 시각이다.
- `Recording.startedAt`은 개별 대원이 실제 기록을 시작한 서버 기준 시각이다.
- `TrackResultVertex.t`와 영상 내부 시간은 개별 기록의 시작점을 0초로 사용한다.
- 세션 시작 후 기록 시작까지의 offset은 `Recording.startedAt - Session.startedAt`으로 계산한다.
- AAR에서 정점 또는 영상의 위치는 `기록 시작 offset + 기록 내부 경과 시간`으로 계산한다.
- `startOffsetSeconds`는 파생 값이므로 Firebase나 Core 모델에 중복 저장하지 않는다.
- 기록 시작 시 대원 앱은 `Recording.startedAt`을 Firestore server timestamp로 즉시 기록한다.
- server timestamp에는 네트워크 처리 지연이 포함될 수 있으며, MVP에서는 이를 허용한다.

## Firebase 구현 시 지켜야 할 경계

- 서버 timestamp 생성은 `CQBFirebase`가 담당한다.
- Firebase DTO와 Core 모델 변환은 `CQBFirebase` 안에서 수행한다.
- 인증과 입장 검증 정보는 Core 모델에 추가하지 않는다.
- View와 Store는 Firebase 경로를 직접 만들지 않는다.
- Security Rules와 실제 연결 끊김 정책은 이 문서의 모델 계약과 분리해 구현한다.

## 결정 기록

2026년 10월 10일 팀 합의와 후속 논의를 통해 다음을 반영했다.

- Firebase에는 다른 기기로 전달해야 하는 최소 데이터만 저장한다.
- `RecordingState.uploading` 대신 `finishing`을 사용한다.
- 업로드 포기 상태인 `failed`를 추가한다.
- 전체 영상 조각 수를 나타내는 `videoChunkCount`를 추가한다.
- 기록 단계 연결 상태 기준으로 `Recording.lastActiveAt`을 추가한다.
- 세션과 개별 기록의 시간축을 연결하기 위해 `Recording.startedAt`을 추가한다.
- 준비 단계는 `Member.lastActiveAt`을 연결 상태 판단에 사용한다.
- `FloorPlanReference.revisionID`와 Storage의 `revisions/` 계층을 제거한다.
- 기록당 하나의 `result.json`만 사용하고 `resultID`, `selectedResultID`를 제거한다.
- 기록 시작 offset은 `Recording.startedAt - Session.startedAt`으로 계산하고 별도로 저장하지 않는다.

2026년 10월 28일 (#98):

- 영상 조각(`chunk_NNNN.mp4`)에 총성 판정용 소리 트랙(AAC-LC, 모노, 64kbps)을 추가한다. 경로, Firestore 문서, Core 모델은 바꾸지 않는다.

2026년 10월 29일 (#100):

- 훈련장 스캔(ARWorldMap)을 `worldMaps/{worldMapID}/`에 스캔 파일과 `setup.json`으로 저장한다.
- `Session.worldMap`(선택)을 추가한다. 없으면 대원이 출발 위치를 직접 정한다.
- AR → 도면 좌표 변환은 교관 앱이 계산해 `setup.json`에 저장하고 대원 앱은 그대로 쓴다.
- 스캔 경로에는 계약한 두 파일만 받는다. 스캔 파일 50MB, `setup.json` 1MB까지 허용한다.
- `WorldMapReference`에 스캔을 만든 도면(`floorPlan`)을 포함하고, 세션 도면과 같아야 한다 (PR #101 리뷰).
