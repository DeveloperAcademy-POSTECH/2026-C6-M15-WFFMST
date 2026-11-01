import AVFoundation
import UIKit
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
        XCTAssertEqual(
            store.selectedFloorPlan?.registeredPlan.flatMap { UIImage(data: $0.image.pngData)?.cgImage?.width },
            1_200
        )
        XCTAssertEqual(
            store.selectedFloorPlan?.registeredPlan.flatMap { UIImage(data: $0.image.pngData)?.cgImage?.height },
            800
        )
        XCTAssertEqual(store.trainingName, "TestFlight 데모 훈련")

        store.openSessionCreation()
        store.createSession()

        let didCreateSession = await waitUntil {
            store.phase == .teamReadiness && store.canStartTraining
        }
        XCTAssertTrue(didCreateSession)
        XCTAssertEqual(store.currentSession?.pin, "012345")
        XCTAssertEqual(
            store.participants.map(\.name),
            ["데모 대원 1", "데모 대원 2", "데모 대원 3", "데모 대원 4", "데모 대원 5", "데모 대원 6"]
        )
        XCTAssertEqual(store.readyCount, 6)

        store.startTraining()

        let didStartTraining = await waitUntil {
            store.phase == .trainingInProgress && store.trainingStartedAt != nil
        }
        XCTAssertTrue(didStartTraining)

        store.finishTraining()

        let didReachResultsPreparation = await waitUntil {
            store.phase == .resultsPreparation
                && store.trainingRecords.rows.count == 6
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

    func testDemoScenarioLoadsSixTracksAndFourSelectedVideosInAAR() async {
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
        XCTAssertEqual(aarStore.tracks.count, 6)
        XCTAssertTrue(aarStore.tracks.values.allSatisfy { state in
            if case .ready = state { return true }
            return false
        })
        XCTAssertEqual(aarStore.playbackDuration, 30, accuracy: 0.001)

        aarStore.setPlaybackPosition(6)
        let positions = participantIDs.compactMap { aarStore.position(for: $0)?.point }
        XCTAssertEqual(positions.count, 6)
        XCTAssertEqual(Set(positions.map { "\($0.x),\($0.y)" }).count, 6)

        participantIDs.prefix(4).reversed().forEach(store.toggleParticipantSelection)
        XCTAssertEqual(store.selectedParticipantIDs, Array(participantIDs.prefix(4)))

        store.toggleParticipantSelection(participantIDs[4])
        XCTAssertEqual(
            store.selectedParticipantIDs,
            [participantIDs[4], participantIDs[0], participantIDs[1], participantIDs[2]]
        )
        let selectedParticipantIDs = store.selectedParticipantIDs
        store.openAARVideoScreen()
        aarStore.showVideos(for: selectedParticipantIDs)
        let didLoadVideos = await waitUntil(attempts: 1_000) {
            selectedParticipantIDs.allSatisfy { id in
                if case .ready? = aarStore.videos[id] { return true }
                return false
            }
        }
        let videoDiagnostics = selectedParticipantIDs.map { id -> String in
            switch aarStore.videos[id] {
            case .loading?: return "\(id): loading"
            case .ready?: return "\(id): ready"
            case .unavailable(let reason)?: return "\(id): \(reason)"
            case nil: return "\(id): missing"
            }
        }.joined(separator: ", ")
        XCTAssertTrue(didLoadVideos, videoDiagnostics)
        XCTAssertEqual(aarStore.playbackDuration, 30, accuracy: 0.1)
        XCTAssertTrue(selectedParticipantIDs.allSatisfy { id in
            if case .playing? = aarStore.videoFrame(for: id) { return true }
            return false
        })

        let reselectedParticipantID = selectedParticipantIDs[3]
        guard case .ready(let uninterruptedPlayer, _)? = aarStore.videos[selectedParticipantIDs[0]],
              case .ready(let reselectedPlayer, _)? = aarStore.videos[reselectedParticipantID],
              let uninterruptedItem = uninterruptedPlayer.currentItem
        else {
            return XCTFail("기존 영상과 재선택할 영상 플레이어가 준비되어야 합니다.")
        }
        let didReachPlaybackPosition = await waitUntil(attempts: 100) {
            abs(uninterruptedPlayer.currentTime().seconds - 6) < 0.1
        }
        XCTAssertTrue(didReachPlaybackPosition)

        store.toggleParticipantMute(selectedParticipantIDs[0])
        store.toggleParticipantMute(reselectedParticipantID)
        uninterruptedPlayer.isMuted = false
        reselectedPlayer.isMuted = false
        aarStore.togglePlayback()
        XCTAssertTrue(aarStore.isPlaying)

        let unexpectedTimeJump = expectation(
            forNotification: .AVPlayerItemTimeJumped,
            object: uninterruptedItem
        )
        unexpectedTimeJump.isInverted = true
        store.toggleParticipantSelection(reselectedParticipantID)
        aarStore.showVideos(for: store.selectedParticipantIDs)
        await fulfillment(of: [unexpectedTimeJump], timeout: 0.2)

        store.toggleParticipantSelection(reselectedParticipantID)
        aarStore.showVideos(for: store.selectedParticipantIDs)
        XCTAssertTrue(reselectedPlayer.isMuted)
        XCTAssertFalse(uninterruptedPlayer.isMuted)

        aarStore.togglePlayback()
        XCTAssertFalse(aarStore.isPlaying)

        store.shutdown()
        aarStore.reset()
        XCTAssertEqual(store.phase, .home)
        XCTAssertTrue(aarStore.tracks.isEmpty)
        XCTAssertTrue(aarStore.videos.isEmpty)
    }

    func testDemoPlaybackSkipsTenSecondsWithinBoundsAndKeepsPlaybackState() async {
        let environment = InstructorDemoScenario.makeEnvironment(processingDelay: .milliseconds(20))
        let store = environment.store
        let aarStore = environment.aarStore

        store.openSessionCreation()
        store.createSession()
        let didCreateSession = await waitUntil {
            store.phase == .teamReadiness && store.canStartTraining
        }
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
        await aarStore.load(
            session: session,
            participantIDs: store.participants.map(\.id),
            localFloorPlan: store.selectedFloorPlan?.registeredPlan
        )
        XCTAssertEqual(aarStore.playbackDuration, 30, accuracy: 0.001)

        aarStore.setPlaybackPosition(5)
        aarStore.skipPlayback(by: -10)
        XCTAssertEqual(aarStore.playbackPosition, 0, accuracy: 0.001)
        XCTAssertFalse(aarStore.isPlaying)

        aarStore.skipPlayback(by: 10)
        XCTAssertEqual(aarStore.playbackPosition, 10, accuracy: 0.001)
        aarStore.setPlaybackPosition(25)
        aarStore.skipPlayback(by: 10)
        XCTAssertEqual(aarStore.playbackPosition, 30, accuracy: 0.001)
        aarStore.skipPlayback(by: 10)
        XCTAssertEqual(aarStore.playbackPosition, 30, accuracy: 0.001)

        aarStore.setPlaybackPosition(15)
        aarStore.togglePlayback()
        aarStore.skipPlayback(by: 10)
        XCTAssertTrue(aarStore.isPlaying)
        XCTAssertEqual(aarStore.playbackPosition, 25, accuracy: 0.2)
        aarStore.togglePlayback()
        XCTAssertFalse(aarStore.isPlaying)

        store.shutdown()
        aarStore.reset()
    }

    func testBundledDemoVideosContainMonoAACAudio() async throws {
        for memberNumber in 1...6 {
            guard let url = Bundle.main.url(
                forResource: "DEBRIEF-Demo-AAR-\(memberNumber)",
                withExtension: "mp4"
            ) else {
                return XCTFail("\(memberNumber)번 데모 영상이 앱 번들에 포함되어야 합니다.")
            }

            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            XCTAssertEqual(duration, 30, accuracy: 0.1)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(audioTracks.count, 1)
            let audioTrack = try XCTUnwrap(
                audioTracks.first,
                "\(memberNumber)번 데모 영상에 오디오 트랙이 있어야 합니다."
            )
            let descriptions = try await audioTrack.load(.formatDescriptions)
            let audioDescription = try XCTUnwrap(descriptions.first)
            let streamDescription = try XCTUnwrap(
                CMAudioFormatDescriptionGetStreamBasicDescription(audioDescription)?.pointee
            )
            XCTAssertEqual(streamDescription.mFormatID, kAudioFormatMPEG4AAC)
            XCTAssertEqual(streamDescription.mChannelsPerFrame, 1)
        }
    }

    func testBundledDemoVideoMakesPlaybackProgressVisible() async throws {
        guard let url = Bundle.main.url(
            forResource: "DEBRIEF-Demo-AAR-1",
            withExtension: "mp4"
        ) else {
            return XCTFail("데모 영상이 앱 번들에 포함되어야 합니다.")
        }

        let asset = AVURLAsset(url: url)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var frames: [Data] = []
        for second in [1.0, 15.0, 29.0] {
            let (image, _) = try await generator.image(
                at: CMTime(seconds: second, preferredTimescale: 600)
            )
            guard let data = UIImage(cgImage: image).pngData() else {
                return XCTFail("데모 영상 프레임을 비교할 수 있어야 합니다.")
            }
            frames.append(data)
        }

        XCTAssertEqual(Set(frames).count, frames.count, "탐색 위치마다 눈으로 구분되는 화면이어야 합니다.")
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
