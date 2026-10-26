import XCTest
@testable import InstructorApp

@MainActor
final class InstructorDemoScenarioTests: XCTestCase {
    func testDemoModeCreatesANewRunWhenRestarted() {
        let demoMode = InstructorDemoMode()
        let initialRunID = demoMode.runID

        demoMode.start()
        let firstRunID = demoMode.runID
        demoMode.stop()
        demoMode.start()

        XCTAssertNotEqual(firstRunID, initialRunID)
        XCTAssertNotEqual(demoMode.runID, firstRunID)
        XCTAssertTrue(demoMode.isActive)
    }

    func testDemoScenarioReachesResultsPreparationWithoutAnExternalDevice() async {
        let store = InstructorDemoScenario.makeStore()

        XCTAssertEqual(store.phase, .home)
        XCTAssertEqual(store.floorPlans.map(\.name), ["데모 훈련장"])
        XCTAssertNotNil(store.selectedFloorPlan?.registeredPlan)
        XCTAssertEqual(store.trainingName, "TestFlight 데모 훈련")

        store.openSessionCreation()
        store.createSession()

        let didCreateSession = await waitUntil {
            store.phase == .teamReadiness && store.canStartTraining
        }
        XCTAssertTrue(didCreateSession)
        XCTAssertEqual(store.currentSession?.pin, "012345")
        XCTAssertEqual(store.participants.map(\.name), ["데모 대원 1", "데모 대원 2", "데모 대원 3"])
        XCTAssertEqual(store.readyCount, 3)

        store.startTraining()

        let didStartTraining = await waitUntil {
            store.phase == .trainingInProgress && store.trainingStartedAt != nil
        }
        XCTAssertTrue(didStartTraining)

        store.finishTraining()

        let didReachResultsPreparation = await waitUntil {
            store.phase == .resultsPreparation
                && store.trainingRecords.rows.count == 3
                && store.trainingRecords.rows.allSatisfy { $0.state.title == "기록 처리·업로드 중" }
        }
        XCTAssertTrue(didReachResultsPreparation)
        XCTAssertEqual(store.phase, .resultsPreparation)
    }

    func testEachDemoStoreStartsFromCleanState() async {
        let firstStore = InstructorDemoScenario.makeStore()
        firstStore.openSessionCreation()
        firstStore.createSession()
        let didCreateSession = await waitUntil { firstStore.phase == .teamReadiness }
        XCTAssertTrue(didCreateSession)

        let restartedStore = InstructorDemoScenario.makeStore()

        XCTAssertEqual(restartedStore.phase, .home)
        XCTAssertNil(restartedStore.currentSession)
        XCTAssertTrue(restartedStore.participants.isEmpty)
        XCTAssertEqual(restartedStore.selectedFloorPlan?.name, "데모 훈련장")
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
