import XCTest
@testable import InstructorApp

@MainActor
final class InstructorStoreTrainingTimerTests: XCTestCase {
    func testStartTrainingSetsStartDateAndDoesNotReplaceIt() {
        let firstStart = Date(timeIntervalSince1970: 1_000)
        let secondStart = Date(timeIntervalSince1970: 2_000)
        var dates = [firstStart, secondStart]
        let store = makeStore(participants: [makeParticipant(id: "ready", isReady: true)]) {
            dates.removeFirst()
        }

        store.startTraining()
        store.startTraining()

        XCTAssertEqual(store.phase, .trainingInProgress)
        XCTAssertEqual(store.trainingStartedAt, firstStart)
        XCTAssertEqual(dates, [secondStart])
    }

    func testStartTrainingExcludingUnreadyParticipantsSetsStartDate() {
        let start = Date(timeIntervalSince1970: 1_000)
        let ready = makeParticipant(id: "ready", isReady: true)
        let unready = makeParticipant(id: "unready", isReady: false)
        let store = makeStore(participants: [ready, unready], now: { start })

        store.startTrainingExcludingUnreadyParticipants()

        XCTAssertEqual(store.phase, .trainingInProgress)
        XCTAssertEqual(store.trainingStartedAt, start)
        XCTAssertEqual(store.participants, [ready])
    }

    func testReturnHomeClearsStartDate() {
        let store = makeStore(
            participants: [makeParticipant(id: "ready", isReady: true)],
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        store.startTraining()

        store.returnHome()

        XCTAssertEqual(store.phase, .home)
        XCTAssertNil(store.trainingStartedAt)
    }

    func testFormattedTrainingElapsedUsesHoursMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(
            participants: [makeParticipant(id: "ready", isReady: true)],
            now: { start }
        )
        store.startTraining()

        XCTAssertEqual(store.formattedTrainingElapsed(at: start), "00:00:00")
        XCTAssertEqual(
            store.formattedTrainingElapsed(at: start.addingTimeInterval(3_723.9)),
            "01:02:03"
        )
        XCTAssertEqual(
            store.formattedTrainingElapsed(at: start.addingTimeInterval(-1)),
            "00:00:00"
        )
    }

    private func makeStore(
        participants: [InstructorParticipant],
        now: @escaping () -> Date
    ) -> InstructorStore {
        let floorPlan = DemoFloorPlan(
            id: "floor-plan",
            name: "테스트 도면",
            fileName: "floor-plan.png",
            referenceDistance: 10
        )
        return InstructorStore(
            floorPlans: [floorPlan],
            now: now,
            previewSession: InstructorPreviewFixture.session(floorPlan: floorPlan.reference),
            previewParticipants: participants
        )
    }

    private func makeParticipant(id: String, isReady: Bool) -> InstructorParticipant {
        InstructorParticipant(
            id: id,
            number: id == "ready" ? 1 : 2,
            name: id,
            isReady: isReady,
            x: 0,
            y: 0
        )
    }
}
