import CQBCore
import XCTest
@testable import InstructorApp

final class AARSoundEventFusionTests: XCTestCase {
    func testGroupsCandidatesWithinWindowAcrossParticipants() {
        let events = AARSoundEventFusion.events(from: [
            "a": [10.0, 30.0],
            "b": [10.3],
            "c": [10.45, 20.0],
        ])

        XCTAssertEqual(events, [
            AARSoundEvent(time: 10.0, participantIDs: ["a", "b", "c"], isCorroborated: true),
            AARSoundEvent(time: 20.0, participantIDs: ["c"], isCorroborated: false),
            AARSoundEvent(time: 30.0, participantIDs: ["a"], isCorroborated: false),
        ])
    }

    func testCandidatesOutsideWindowBecomeSeparateEvents() {
        let events = AARSoundEventFusion.events(from: ["a": [10.0], "b": [10.6]])

        XCTAssertEqual(events.map(\.time), [10.0, 10.6])
        XCTAssertEqual(events.map(\.isCorroborated), [false, false])
    }

    func testSameParticipantTwiceIsNotCorroboration() {
        let events = AARSoundEventFusion.events(from: ["a": [10.0, 10.2]])

        XCTAssertEqual(events, [AARSoundEvent(time: 10.0, participantIDs: ["a"], isCorroborated: false)])
    }

    func testMinimumParticipantsCanChange() {
        let candidates = ["a": [10.0], "b": [10.1], "c": [10.2]]

        XCTAssertTrue(AARSoundEventFusion.events(from: candidates, minimumParticipants: 3)[0].isCorroborated)
        XCTAssertFalse(AARSoundEventFusion.events(from: candidates, minimumParticipants: 4)[0].isCorroborated)
        XCTAssertTrue(AARSoundEventFusion.events(from: [:]).isEmpty)
    }
}

@MainActor
final class AARSoundEventStoreTests: XCTestCase {
    // @MainActor 객체를 쓰는 테스트는 async로 둔다(#161).
    func testDemoHistoryShowsSoundEventsAndJumpsToEvent() async throws {
        let environment = InstructorDemoScenario.makeEnvironment()
        let store = environment.store
        let aarStore = environment.aarStore
        let record = try XCTUnwrap(store.trainingHistory.first)

        store.openTrainingHistoryRecord(record.sessionID)
        try await waitUntil { store.phase == .aar }
        let session = try XCTUnwrap(store.currentSession)
        await aarStore.load(session: session, participantIDs: store.participants.map(\.id), localFloorPlan: nil)

        // 마커는 AAR 로딩과 따로 받는다. 21.5초는 한 대원만 들어 표시하지 않는다.
        try await waitUntil { !aarStore.soundEvents.isEmpty }
        XCTAssertEqual(aarStore.soundEvents.map(\.time), [6.20, 14.80, 26.00])
        XCTAssertEqual(aarStore.soundEvents.map(\.participantIDs.count), [4, 3, 2])

        try await waitUntil { aarStore.playbackDuration > 0 }
        let event = try XCTUnwrap(aarStore.soundEvents.dropFirst().first)
        aarStore.jumpToSoundEvent(event)
        XCTAssertEqual(aarStore.playbackPosition, 14.80, accuracy: 0.001, "마커 시각으로 바로 이동")

        aarStore.reset()
        XCTAssertTrue(aarStore.soundEvents.isEmpty)
    }

    func testRealRecordingsHaveNoSoundEventsUntilContract() async {
        let aarStore = AARStore()
        let session = Session(id: UUID(), pin: "000168", name: "검사", status: .ended, startedAt: .now, floorPlan: FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "x"))
        await aarStore.load(session: session, participantIDs: [], localFloorPlan: nil)

        XCTAssertTrue(aarStore.soundEvents.isEmpty)
    }

    func testSlowSoundCandidatesDoNotBlockAARLoading() async {
        let identity = TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID())
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let recording = Recording(identity: identity, state: .done, startedAt: startedAt, lastActiveAt: startedAt)
        let loader = HangingSoundCandidateLoader()
        let aarStore = AARStore(
            recordingRepository: SingleRecordingRepository(recording: recording),
            soundCandidateLoader: loader
        )
        let session = Session(id: identity.sessionID, pin: "000175", name: "검사", status: .ended, startedAt: startedAt, floorPlan: FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "x"))

        await aarStore.load(session: session, participantIDs: [identity.memberID.uuidString], localFloorPlan: nil)

        XCTAssertFalse(aarStore.isLoading, "후보 다운로드가 끝나지 않아도 AAR 로딩은 끝난다")
        XCTAssertTrue(aarStore.soundEvents.isEmpty)
        aarStore.reset()
        let didCancel = await loader.waitForCancellation()
        XCTAssertTrue(didCancel, "reset하면 후보 다운로드를 취소한다")
    }

    /// 조건이 3초 안에 맞지 않으면 오류를 던져 테스트를 멈춘다. 이어서 배열을 읽다가 범위 초과로 죽지 않게 한다.
    private func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("시간 내 상태 도달 실패", file: file, line: line)
        throw WaitTimeout()
    }
}

private struct WaitTimeout: Error {}

/// 취소될 때까지 끝나지 않는 후보 다운로드.
private actor HangingSoundCandidateLoader: AARSoundCandidateLoading {
    private var cancelled = false

    func candidates(for identity: TrackIdentity) async throws -> [AARSoundCandidate] {
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch {
            cancelled = true
            throw error
        }
        return []
    }

    func waitForCancellation() async -> Bool {
        for _ in 0..<300 {
            if cancelled { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private struct SingleRecordingRepository: RecordingRepository {
    let recording: Recording

    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {}
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([recording])
            continuation.finish()
        }
    }
}
