import CQBCore
import XCTest
@testable import InstructorApp

@MainActor
final class InstructorStoreTrainingTimerTests: XCTestCase {
    func testTimerWaitsForServerStartDate() {
        let store = makeStore(startedAt: nil)

        XCTAssertNil(store.trainingStartedAt)
        XCTAssertNil(store.trainingElapsed(at: Date(timeIntervalSince1970: 2_000)))
        XCTAssertEqual(store.formattedTrainingElapsed(at: Date(timeIntervalSince1970: 2_000)), "00:00:00")
    }

    func testTimerUsesServerStartDate() {
        let start = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(startedAt: start)

        XCTAssertEqual(store.trainingStartedAt, start)
        XCTAssertEqual(store.trainingElapsed(at: start), "00:00:00")
        XCTAssertEqual(store.trainingElapsed(at: start.addingTimeInterval(3_723.9)), "01:02:03")
        XCTAssertEqual(store.trainingElapsed(at: start.addingTimeInterval(-1)), "00:00:00")
    }

    func testReturnHomeClearsServerStartDate() {
        let store = makeStore(startedAt: Date(timeIntervalSince1970: 1_000))

        store.returnHome()

        XCTAssertEqual(store.phase, .home)
        XCTAssertNil(store.trainingStartedAt)
    }

    func testFormatTrainingElapsedUsesHoursMinutesAndSeconds() {
        XCTAssertEqual(InstructorStore.formatTrainingElapsed(0), "00:00:00")
        XCTAssertEqual(InstructorStore.formatTrainingElapsed(3_723.9), "01:02:03")
        XCTAssertEqual(InstructorStore.formatTrainingElapsed(-1), "00:00:00")
    }

    private func makeStore(startedAt: Date?) -> InstructorStore {
        let floorPlan = InstructorFloorPlan(
            id: "floor-plan",
            name: "테스트 도면",
            fileName: "floor-plan.png",
            referenceDistance: 10
        )
        let session = Session(
            id: UUID(),
            pin: "123456",
            name: "타이머 테스트",
            status: .running,
            startedAt: startedAt,
            floorPlan: floorPlan.reference
        )
        return InstructorStore(
            floorPlans: [floorPlan],
            previewSession: session,
            previewParticipants: [makeParticipant()],
            previewPhase: .trainingInProgress
        )
    }

    private func makeParticipant() -> InstructorParticipant {
        InstructorParticipant(
            id: "ready",
            number: 1,
            name: "ready",
            isReady: true,
            x: 0,
            y: 0
        )
    }
}
