import CQBCore
import XCTest
@testable import InstructorApp

@MainActor
final class InstructorStoreTrainingTimerTests: XCTestCase {
    // Xcode 27 + iOS 26 런타임에서 동기 테스트가 끝날 때 @MainActor 객체 해제가 크래시해 async로 둔다(#161).
    func testTimerWaitsForServerStartDate() async {
        let store = makeStore(startedAt: nil)

        XCTAssertNil(store.trainingStartedAt)
        XCTAssertNil(store.trainingElapsed(at: Date(timeIntervalSince1970: 2_000)))
        XCTAssertEqual(store.formattedTrainingElapsed(at: Date(timeIntervalSince1970: 2_000)), "00:00")
    }

    func testTimerUsesServerStartDate() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(startedAt: start)

        XCTAssertEqual(store.trainingStartedAt, start)
        XCTAssertEqual(store.trainingElapsed(at: start), "00:00")
        XCTAssertEqual(store.trainingElapsed(at: start.addingTimeInterval(3_723.9)), "62:03")
        XCTAssertEqual(store.trainingElapsed(at: start.addingTimeInterval(-1)), "00:00")
    }

    func testTimerStopsWhenResultsPreparationBegins() async throws {
        let start = Date(timeIntervalSinceNow: -120)
        let store = makeStore(startedAt: start)

        store.finishTraining()

        let didFinish = await waitUntil { store.phase == .resultsPreparation }
        XCTAssertTrue(didFinish)
        let endedAt = try XCTUnwrap(store.trainingEndedAt)
        let elapsedAtEnd = try XCTUnwrap(store.trainingElapsed(at: endedAt))

        XCTAssertEqual(store.trainingElapsed(at: endedAt.addingTimeInterval(60)), elapsedAtEnd)
        XCTAssertEqual(store.trainingHistory.first?.endedAt, endedAt)
    }

    func testFailedFinishKeepsTimerRunning() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(startedAt: start, sessionRepository: FailingSessionRepository())

        store.finishTraining()

        let didFail = await waitUntil { store.trainingActionError != nil }
        XCTAssertTrue(didFail)
        XCTAssertEqual(store.phase, .trainingInProgress)
        XCTAssertNil(store.trainingEndedAt)
        XCTAssertEqual(store.trainingElapsed(at: start.addingTimeInterval(10)), "00:10")
        XCTAssertEqual(store.trainingElapsed(at: start.addingTimeInterval(20)), "00:20")
    }

    func testReturnHomeClearsServerStartDate() async {
        let store = makeStore(startedAt: Date(timeIntervalSince1970: 1_000))

        store.returnHome()

        XCTAssertEqual(store.phase, .home)
        XCTAssertNil(store.trainingStartedAt)
        XCTAssertNil(store.trainingEndedAt)
    }

    func testFormatTrainingElapsedUsesAccumulatedMinutesAndSeconds() {
        XCTAssertEqual(InstructorStore.formatTrainingElapsed(0), "00:00")
        XCTAssertEqual(InstructorStore.formatTrainingElapsed(3_723.9), "62:03")
        XCTAssertEqual(InstructorStore.formatTrainingElapsed(-1), "00:00")
    }

    private func makeStore(
        startedAt: Date?,
        sessionRepository: any SessionRepository = DemoSessionRepository()
    ) -> InstructorStore {
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
            sessionRepository: sessionRepository,
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

    private func waitUntil(
        attempts: Int = 100,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private struct FailingSessionRepository: SessionRepository {
    private enum UpdateError: Error { case failed }

    func createSession(_ session: Session) async throws {}
    func session(forPin pin: String) async throws -> Session { throw RepositoryError.notFound }
    func updateStatus(of session: Session, to status: SessionStatus) async throws { throw UpdateError.failed }
    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
