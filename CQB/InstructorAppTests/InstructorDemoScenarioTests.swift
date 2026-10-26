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

        store.shutdown()

        XCTAssertEqual(store.phase, .home)
        XCTAssertNil(store.currentSession)
        XCTAssertTrue(store.participants.isEmpty)
        XCTAssertTrue(store.trainingRecords.rows.isEmpty)
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

        firstStore.shutdown()
        restartedStore.shutdown()
    }

    func testDemoScenarioLoadsThreeTracksAndBundledVideosInAAR() async {
        let environment = InstructorDemoScenario.makeEnvironment(processingDelay: .milliseconds(20))
        let store = environment.store
        let aarStore = environment.aarStore

        store.openSessionCreation()
        store.createSession()
        let didCreateSession = await waitUntil { store.phase == .teamReadiness && store.canStartTraining }
        XCTAssertTrue(didCreateSession)

        store.startTraining()
        let didStartTraining = await waitUntil { store.phase == .trainingInProgress }
        XCTAssertTrue(didStartTraining)
        store.finishTraining()
        let didEnterAAR = await waitUntil { store.phase == .aar }
        XCTAssertTrue(didEnterAAR)

        guard let session = store.currentSession else {
            return XCTFail("데모 세션이 유지되어야 합니다.")
        }
        let participantIDs = store.participants.map(\.id)
        await aarStore.load(
            session: session,
            participantIDs: participantIDs,
            localFloorPlan: store.selectedFloorPlan?.registeredPlan
        )

        XCTAssertEqual(aarStore.floorPlanImageSize?.width, 1_200)
        XCTAssertEqual(aarStore.floorPlanImageSize?.height, 800)
        XCTAssertEqual(aarStore.tracks.count, 3)
        XCTAssertTrue(aarStore.tracks.values.allSatisfy { state in
            if case .ready = state { return true }
            return false
        })
        XCTAssertEqual(aarStore.playbackDuration, 12, accuracy: 0.001)

        aarStore.setPlaybackPosition(6)
        let positions = participantIDs.compactMap { aarStore.position(for: $0)?.point }
        XCTAssertEqual(positions.count, 3)
        XCTAssertEqual(Set(positions.map { "\($0.x),\($0.y)" }).count, 3)

        store.changeAARMode(to: .video)
        aarStore.showVideos(for: participantIDs)
        let didLoadVideos = await waitUntil(attempts: 1_000) {
            participantIDs.allSatisfy { id in
                if case .ready? = aarStore.videos[id] { return true }
                return false
            }
        }
        let videoDiagnostics = participantIDs.map { id -> String in
            switch aarStore.videos[id] {
            case .loading?: return "\(id): loading"
            case .ready?: return "\(id): ready"
            case .unavailable(let reason)?: return "\(id): \(reason)"
            case nil: return "\(id): missing"
            }
        }.joined(separator: ", ")
        XCTAssertTrue(didLoadVideos, videoDiagnostics)
        XCTAssertEqual(aarStore.playbackDuration, 12, accuracy: 0.1)
        XCTAssertTrue(participantIDs.allSatisfy { id in
            if case .playing? = aarStore.videoFrame(for: id) { return true }
            return false
        })

        aarStore.togglePlayback()
        XCTAssertTrue(aarStore.isPlaying)
        aarStore.togglePlayback()
        XCTAssertFalse(aarStore.isPlaying)

        store.shutdown()
        aarStore.reset()
        XCTAssertEqual(store.phase, .home)
        XCTAssertTrue(aarStore.tracks.isEmpty)
        XCTAssertTrue(aarStore.videos.isEmpty)
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
