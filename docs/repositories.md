# Repository 사용법

앱의 Store가 Firestore에 저장하고, 읽고, 실시간으로 받는 방법을 정리한다.
저장 경로와 필드 계약은 [CQB 공유 데이터 계약](cqb-core-models.md)을 따른다.

## 구성

| 위치 | 내용 |
| --- | --- |
| `CQBCore/Repositories/` | 앱이 의존하는 프로토콜과 `RepositoryError` |
| `CQBFirebase/Repositories/` | Firestore 구현 (`FirestoreSessionRepository` 등) |

Store는 `CQBCore`의 프로토콜만 안다. Firebase 구현을 아는 곳은 각 앱의 `AppContainer`뿐이다.

## 사전 준비

- 앱 타깃이 `CQBCore`와 `CQBFirebase`를 링크하고, 앱 폴더에 `GoogleService-Info.plist`가 있어야 한다.
- 앱 시작 시 `CQBFirebaseModule.configure()`와 `CQBFirebaseModule.signInAnonymously()`를 부른다. 두 앱의 `App` 진입점에 이미 있다.
- Firebase 콘솔에서 익명 로그인이 켜져 있어야 한다.
- Firestore 규칙이 로그인한 사용자의 읽기·쓰기를 허용해야 한다. 막혀 있으면 모든 요청이 권한 오류(code 7)로 실패한다. 현재 개발용 규칙은 다음과 같다.

```
match /{document=**} {
  allow read, write: if request.auth != null;
}
```

## 누가 무엇을 부르나

보내는 쪽이 저장하고, 받는 쪽이 구독한다.

| Repository | 교관 앱 (iPad) | 대원 앱 (iPhone) |
| --- | --- | --- |
| `SessionRepository` | `createSession`, `updateStatus` | `session(forPin:)`, `observeSession` |
| `MemberRepository` | `observeMembers` | `join`, `updateReadiness` |
| `RecordingRepository` | `observeRecordings` | `startRecording`, `updateRecording` |

## Store에 넣기

Store는 프로토콜 타입으로 받는다.

```swift
import CQBCore

@MainActor
@Observable
final class MemberStore {
    @ObservationIgnored private let sessionRepository: any SessionRepository
    @ObservationIgnored private let memberRepository: any MemberRepository
    @ObservationIgnored private let recordingRepository: any RecordingRepository

    init(
        sessionRepository: any SessionRepository,
        memberRepository: any MemberRepository,
        recordingRepository: any RecordingRepository
    ) {
        self.sessionRepository = sessionRepository
        self.memberRepository = memberRepository
        self.recordingRepository = recordingRepository
    }
}
```

실제 구현은 `AppContainer`에서 넣는다.

```swift
import CQBFirebase

struct AppContainer: View {
    @State private var store = MemberStore(
        sessionRepository: FirestoreSessionRepository(),
        memberRepository: FirestoreMemberRepository(),
        recordingRepository: FirestoreRecordingRepository()
    )
}
```

## 한 번 저장·읽기

```swift
func join(pin: String, name: String) async {
    do {
        let session = try await sessionRepository.session(forPin: pin)
        let member = Member(id: memberID, sessionID: session.id, name: name,
                            isReady: false, lastActiveAt: .now)
        try await memberRepository.join(member, pin: pin)
    } catch RepositoryError.notFound {
        // 없는 PIN
    } catch RepositoryError.sessionClosed {
        // 이미 시작했거나 끝난 훈련
    } catch {
        // 네트워크 등
    }
}
```

교관 앱에서 세션을 만들 때는 PIN 중복에 대비해 몇 번 다시 시도한다.

```swift
func createSession(name: String, floorPlan: FloorPlanReference) async throws -> Session {
    for _ in 0..<5 {
        let session = Session(id: UUID(), pin: makePin(), name: name,
                              status: .waiting, floorPlan: floorPlan)
        do {
            try await sessionRepository.createSession(session)
            return session
        } catch RepositoryError.pinTaken {
            continue
        }
    }
    throw RepositoryError.pinTaken
}

// 훈련 시작·종료
try await sessionRepository.updateStatus(of: session, to: .running)
try await sessionRepository.updateStatus(of: session, to: .ended)
```

대원 앱의 기록은 시작 → 마무리 → 완료 순서로 보낸다.

```swift
let identity = TrackIdentity(sessionID: session.id, memberID: member.id, recordingID: UUID())

try await recordingRepository.startRecording(
    Recording(identity: identity, state: .recording, lastActiveAt: .now))
// 녹화 끝
try await recordingRepository.updateRecording(
    Recording(identity: identity, state: .finishing, lastActiveAt: .now, videoChunkCount: chunkCount))
// 결과와 영상 업로드 끝 (포기하면 .failed)
try await recordingRepository.updateRecording(
    Recording(identity: identity, state: .done, lastActiveAt: .now, videoChunkCount: chunkCount))
```

## 실시간으로 받기

구독은 `Task`에 담아 두고, 필요 없어지면 `cancel()`한다. 스트림이 끝나면 Firestore 리스너도 해제된다.
처음 구독하면 현재 값이 한 번 바로 온다.

```swift
@ObservationIgnored private var sessionTask: Task<Void, Never>?

func startObservingSession(id: UUID) {
    sessionTask = Task {
        do {
            for try await session in sessionRepository.observeSession(id: id) {
                if session.status == .running { /* 녹화 시작 */ }
                if session.status == .ended { break }
            }
        } catch {
            // 연결 끊김
        }
    }
}

func stopObservingSession() {
    sessionTask?.cancel()
    sessionTask = nil
}
```

교관 앱은 대원 준비 현황과 기록 상태를 같은 방식으로 받는다.

```swift
for try await members in memberRepository.observeMembers(sessionID: session.id) {
    self.members = members
}

for try await recordings in recordingRepository.observeRecordings(sessionID: session.id) {
    let finished = recordings.allSatisfy { $0.state == .done || $0.state == .failed }
    if finished { /* AAR로 이동 */ break }
}
```

상태가 빠르게 바뀌면 중간 값 없이 마지막 값만 올 수 있다. 화면은 받은 최신 값만 기준으로 그린다.

## 주기적으로 보내기 (생존 신호)

```swift
@ObservationIgnored private var heartbeatTask: Task<Void, Never>?

func startHeartbeat(member: Member) {
    heartbeatTask = Task {
        while !Task.isCancelled {
            try? await memberRepository.updateReadiness(of: member)
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
```

갱신 주기와 연결 끊김 판단 시간은 아직 정하지 않았다. 위의 5초는 예시다.

## 함수별 주의사항

### SessionRepository

- `createSession`: PIN은 앱이 만든다. 이미 쓰이는 PIN이면 `RepositoryError.pinTaken`을 던지므로 새 PIN으로 다시 시도한다.
- `session(forPin:)`: 없는 PIN이거나 종료된 세션이면 `RepositoryError.notFound`.
- `updateStatus`: 상태는 `preparing → waiting → running → ended` 방향으로만 바뀐다. 중간 단계는 건너뛸 수 있다.
  - 같은 상태로 다시 부르면 아무것도 바꾸지 않는다. `startedAt`도 다시 기록하지 않는다.
  - 이전 단계로 되돌리면 `RepositoryError.invalidStatusChange`.
  - `running`이면 `startedAt`을 서버 시각으로 기록한다. `ended`면 PIN을 지워 다시 쓸 수 있게 한다.
- `observeSession`: 대원 앱은 신호를 놓치지 않도록 입장 직후부터 `ended`를 받을 때까지 구독한다.

### MemberRepository

- `join`: 입장할 때 한 번 부른다. 입장 검증용 `pin`과 인증 `uid`를 함께 저장한다.
  - PIN이 없거나 다른 세션을 가리키면 `RepositoryError.notFound`.
  - 훈련이 시작했거나 끝났으면(`running`, `ended`) `RepositoryError.sessionClosed`. 입장은 `preparing`, `waiting`에서만 된다.
- `updateReadiness`: `isReady`와 `lastActiveAt`만 바꾼다. 문서가 있어야 하므로 `join` 다음에만 부른다.

### RecordingRepository

- `startRecording`: 기록을 시작할 때 한 번 부른다. `startedAt`과 `lastActiveAt`을 서버 시각으로 기록한다.
- `updateRecording`: 상태 변경(`finishing`, `done`, `failed`)과 생존 신호에 쓴다. 모델에서 `nil`인 값은 서버에 있던 값을 지우지 않는다.

### 공통

- `RepositoryError` 외의 에러는 Firebase 에러가 그대로 온다. 예: 권한 오류(code 7), 네트워크 오류(code 14). 화면에는 "네트워크를 확인해 주세요" 같은 공통 메시지로 처리한다.

- 모델의 `lastActiveAt`, `startedAt`에 넣은 값은 저장할 때 서버 시각으로 바뀐다. `.now`를 넣어도 된다.
- 모든 함수는 익명 로그인이 끝날 때까지 기다린 뒤 요청한다. 앱 시작 직후에 불러도 된다.

## 아직 없는 것

- `CQBFixtures`의 가짜 구현 (Preview·테스트용)
- Storage 업로드 (도면 파일, 보정 결과, 영상 조각)
