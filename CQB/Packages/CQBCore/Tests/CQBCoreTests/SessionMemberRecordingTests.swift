import Foundation
import Testing
@testable import CQBCore

@Test("SessionStatus의 모든 상태가 Codable 왕복된다")
func sessionStatusCodableRoundTrip() throws {
    let statuses: [SessionStatus] = [.preparing, .waiting, .running, .ended]

    for status in statuses {
        let decoded = try codableRoundTrip(status)
        #expect(decoded.rawValue == status.rawValue)
    }
}

@Test("Session이 세션의 서버 시작 시각과 도면 참조를 보존한다")
func sessionCodableRoundTrip() throws {
    let floorPlan = FloorPlanReference(
        floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        navigationSHA256: "navigation-sha256"
    )
    let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let session = Session(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
        pin: "123456",
        name: "오후 훈련",
        status: .running,
        startedAt: startedAt,
        floorPlan: floorPlan
    )

    let decoded = try codableRoundTrip(session)

    #expect(decoded.id == session.id)
    #expect(decoded.pin == session.pin)
    #expect(decoded.name == session.name)
    #expect(decoded.status.rawValue == session.status.rawValue)
    #expect(decoded.startedAt == startedAt)
    #expect(decoded.floorPlan == floorPlan)
}

@Test("Session은 시작 전 nil 서버 시각을 표현할 수 있다")
func sessionWithoutStartedAt() throws {
    let session = Session(
        id: UUID(),
        pin: "654321",
        name: "시작 전 훈련",
        status: .waiting,
        floorPlan: FloorPlanReference(
            floorPlanID: UUID(),
            navigationSHA256: "navigation-sha256"
        )
    )

    let decoded = try codableRoundTrip(session)

    #expect(decoded.startedAt == nil)
}

@Test("Member가 세션과 대원 식별자, 준비 상태를 보존한다")
func memberCodableRoundTrip() throws {
    let readyUpdatedAt = Date(timeIntervalSince1970: 1_800_000_100)
    let member = Member(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
        name: "대원 1",
        isReady: true,
        readyUpdatedAt: readyUpdatedAt
    )

    let decoded = try codableRoundTrip(member)

    #expect(decoded.id == member.id)
    #expect(decoded.sessionID == member.sessionID)
    #expect(decoded.name == member.name)
    #expect(decoded.isReady)
    #expect(decoded.readyUpdatedAt == readyUpdatedAt)
}

@Test("RecordingState의 모든 상태가 Codable 왕복된다")
func recordingStateCodableRoundTrip() throws {
    let states: [RecordingState] = [.recording, .finishing, .done, .failed]

    for state in states {
        let decoded = try codableRoundTrip(state)
        #expect(decoded.rawValue == state.rawValue)
    }
}

@Test("Recording.id는 TrackIdentity의 recordingID와 일치한다")
func recordingUsesIdentityID() {
    let identity = TrackIdentity(
        sessionID: UUID(),
        memberID: UUID(),
        recordingID: UUID()
    )
    let recording = Recording(
        identity: identity,
        state: .recording,
        lastActiveAt: Date(timeIntervalSince1970: 1_800_000_200)
    )

    #expect(recording.id == identity.recordingID)
}

@Test("녹화 중에는 영상 조각 전체 개수가 nil일 수 있다")
func recordingWithoutVideoChunkCount() throws {
    let recording = Recording(
        identity: TrackIdentity(
            sessionID: UUID(),
            memberID: UUID(),
            recordingID: UUID()
        ),
        state: .recording,
        lastActiveAt: Date(timeIntervalSince1970: 1_800_000_200)
    )

    let decoded = try codableRoundTrip(recording)

    #expect(decoded.videoChunkCount == nil)
    #expect(decoded.state.rawValue == RecordingState.recording.rawValue)
}

@Test("녹화 종료 후 확정한 영상 조각 전체 개수가 보존된다")
func recordingWithVideoChunkCount() throws {
    let identity = TrackIdentity(
        sessionID: UUID(),
        memberID: UUID(),
        recordingID: UUID()
    )
    let recording = Recording(
        identity: identity,
        state: .done,
        lastActiveAt: Date(timeIntervalSince1970: 1_800_000_200),
        videoChunkCount: 7
    )

    let decoded = try codableRoundTrip(recording)

    #expect(decoded.identity == identity)
    #expect(decoded.state.rawValue == RecordingState.done.rawValue)
    #expect(decoded.videoChunkCount == 7)
}

@Test("Recording이 마지막 활동 서버 시각을 보존한다")
func recordingPreservesLastActiveAt() throws {
    let lastActiveAt = Date(timeIntervalSince1970: 1_800_000_200)
    let recording = Recording(
        identity: TrackIdentity(
            sessionID: UUID(),
            memberID: UUID(),
            recordingID: UUID()
        ),
        state: .recording,
        lastActiveAt: lastActiveAt
    )

    let decoded = try codableRoundTrip(recording)

    #expect(decoded.lastActiveAt == lastActiveAt)
}

@Test("Recording이 서버 기준 기록 시작 시각을 보존한다")
func recordingPreservesStartedAt() throws {
    let startedAt = Date(timeIntervalSince1970: 1_800_000_150)
    let recording = Recording(
        identity: TrackIdentity(
            sessionID: UUID(),
            memberID: UUID(),
            recordingID: UUID()
        ),
        state: .recording,
        startedAt: startedAt,
        lastActiveAt: Date(timeIntervalSince1970: 1_800_000_200)
    )

    let decoded = try codableRoundTrip(recording)

    #expect(decoded.startedAt == startedAt)
}

@Test("Recording은 서버 시작 시각이 확정되기 전 nil을 표현할 수 있다")
func recordingWithoutStartedAt() throws {
    let recording = Recording(
        identity: TrackIdentity(
            sessionID: UUID(),
            memberID: UUID(),
            recordingID: UUID()
        ),
        state: .recording,
        lastActiveAt: Date(timeIntervalSince1970: 1_800_000_200)
    )

    let decoded = try codableRoundTrip(recording)

    #expect(decoded.startedAt == nil)
}
