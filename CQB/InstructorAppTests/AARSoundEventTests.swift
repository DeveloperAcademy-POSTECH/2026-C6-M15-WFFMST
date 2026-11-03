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

        // 21.5초는 한 대원만 들어 표시하지 않는다.
        XCTAssertEqual(aarStore.soundEvents.map(\.time), [6.20, 14.80, 26.00])
        XCTAssertEqual(aarStore.soundEvents.map(\.participantIDs.count), [4, 3, 2])

        try await waitUntil { aarStore.playbackDuration > 0 }
        aarStore.jumpToSoundEvent(aarStore.soundEvents[1])
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

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("시간 내 상태 도달 실패")
    }
}
