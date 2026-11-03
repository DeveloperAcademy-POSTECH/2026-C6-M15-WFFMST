import CQBCore
import XCTest
@testable import MemberApp

@MainActor
final class MemberPositioningTests: XCTestCase {
    func testDemoOffersManualSetupOnlyAfterScanTimeoutWithoutReportingReady() async throws {
        let environment = MemberDemoScenario.makeEnvironment(relocalizationTimeout: .milliseconds(30))
        let store = environment.store
        environment.enter()
        defer { store.shutdown() }
        XCTAssertEqual(store.phase, .waiting)
        XCTAssertFalse(store.canSetPositionManually)
        XCTAssertEqual(store.positioningState, .relocalizing)
        store.cameraScreenVisibilityChanged(true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(store.canSetPositionManually)
        store.updateTrackingReadiness(true)
        XCTAssertFalse(store.isReady)
        store.resetPosition()
        XCTAssertEqual(store.phase, .setup)
        XCTAssertTrue(store.isSetupFromCamera)
        store.returnFromPositionSetup()
        XCTAssertEqual(store.phase, .waiting)
        XCTAssertTrue(store.canSetPositionManually)
    }

    func testManualConfirmationRequiresFreshTrackingBeforeReady() async throws {
        let environment = MemberDemoScenario.makeEnvironment(relocalizationTimeout: .milliseconds(30))
        let store = environment.store
        environment.enter()
        defer { store.shutdown() }
        let map = try XCTUnwrap(store.trainingMap)
        let point = PositioningTestData.freePixel(map)
        store.cameraScreenVisibilityChanged(true)
        try await Task.sleep(for: .milliseconds(80))
        store.resetPosition()
        store.confirmPosition(start: CGPoint(x: point.x / Double(map.manifest.imageWidth), y: point.y / Double(map.manifest.imageHeight)),
                              direction: CGPoint(x: (point.x + 20) / Double(map.manifest.imageWidth), y: point.y / Double(map.manifest.imageHeight)))
        XCTAssertEqual(store.phase, .waiting)
        XCTAssertEqual(store.positioningState, .manualReady)
        XCTAssertFalse(store.isReady)
        store.updatePositioning(pose: nil, isNormal: true, trackingReady: true)
        XCTAssertTrue(store.isReady)
        store.cameraSessionRunningChanged(false)
        XCTAssertFalse(store.isReady)
    }

    func testDemoTrackingCannotCompleteSimulatedScanOrCancelTimeout() async throws {
        let environment = MemberDemoScenario.makeEnvironment(relocalizationTimeout: .milliseconds(30))
        let store = environment.store
        environment.enter()
        defer { store.shutdown() }
        store.cameraScreenVisibilityChanged(true)
        store.cameraSessionRunningChanged(true)
        store.updatePositioning(pose: ARPose(x: 0, y: 1, z: 0, forwardX: 1, forwardZ: 0),
                                isNormal: true, trackingReady: true)
        XCTAssertFalse(store.isReady)
        XCTAssertNil(store.startPoint)
        XCTAssertEqual(store.positioningState, .relocalizing)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.positioningState, .manualAvailable)
        XCTAssertTrue(store.canSetPositionManually)
    }

    func testDemoScreenPauseCancelsScanAndManualRoundTripDoesNotRepeatIt() async throws {
        let environment = MemberDemoScenario.makeEnvironment(relocalizationTimeout: .milliseconds(30))
        let store = environment.store
        environment.enter()
        defer { store.shutdown() }
        store.cameraScreenVisibilityChanged(true)
        store.cameraScreenVisibilityChanged(false)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.positioningState, .relocalizing)
        XCTAssertFalse(store.canSetPositionManually)
        store.cameraScreenVisibilityChanged(true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(store.canSetPositionManually)
        store.resetPosition()
        store.cameraScreenVisibilityChanged(false)
        store.returnFromPositionSetup()
        store.cameraScreenVisibilityChanged(true)
        XCTAssertFalse(store.isSimulatingDemoScan)
        XCTAssertTrue(store.canSetPositionManually)
        XCTAssertEqual(store.positioningState, .manualRequired)
    }

    func testTimeoutOffersManualSetupAndLateSuccessfulRecognitionRecovers() async throws {
        let fixture = try makeFixture()
        let store = fixture.store
        defer { store.shutdown() }
        store.cameraSessionRunningChanged(true)
        XCTAssertFalse(store.canSetPositionManually)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.positioningState, .manualAvailable)
        XCTAssertTrue(store.canSetPositionManually)
        store.updatePositioning(pose: fixture.pose, isNormal: true, trackingReady: true)
        XCTAssertEqual(store.positioningState, .automaticReady)
        XCTAssertTrue(store.isReady)
        XCTAssertFalse(store.canSetPositionManually)
    }

    func testRecognitionBeforeTimeoutCancelsFallbackAndTracksCurrentPose() async throws {
        let fixture = try makeFixture()
        let store = fixture.store
        defer { store.shutdown() }
        store.cameraSessionRunningChanged(true)
        store.updatePositioning(pose: fixture.pose, isNormal: true, trackingReady: true)
        let start = try XCTUnwrap(store.startPoint)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.positioningState, .automaticReady)
        XCTAssertEqual(store.startPoint, start)
        store.updatePositioning(pose: nil, isNormal: false, trackingReady: false)
        XCTAssertFalse(store.isReady)
        XCTAssertNil(store.startPoint)
        XCTAssertNil(store.directionPoint)
    }

    func testManualSwitchIgnoresLateAutomaticPoseAndDoesNotRestartTimer() async throws {
        let fixture = try makeFixture()
        let store = fixture.store
        defer { store.shutdown() }
        store.cameraSessionRunningChanged(true)
        try await Task.sleep(for: .milliseconds(80))
        store.resetPosition()
        XCTAssertEqual(store.phase, .setup)
        store.returnFromPositionSetup()
        store.cameraSessionRunningChanged(true)
        store.updatePositioning(pose: fixture.pose, isNormal: true, trackingReady: true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.positioningState, .manualRequired)
        XCTAssertTrue(store.canSetPositionManually)
        XCTAssertFalse(store.isReady)
        XCTAssertNil(store.startPoint)
    }

    func testCameraPauseCancelsTimeoutAndRestartGetsNewAttempt() async throws {
        let fixture = try makeFixture()
        let store = fixture.store
        defer { store.shutdown() }
        store.cameraSessionRunningChanged(true)
        store.cameraSessionRunningChanged(false)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.positioningState, .relocalizing)
        XCTAssertFalse(store.canSetPositionManually)
        store.cameraSessionRunningChanged(true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(store.canSetPositionManually)
    }

    func testOperatingSessionWithoutWorldMapKeepsInitialManualFlow() async throws {
        let map = try BundledTrainingMapLoader.load()
        let repository = PositioningRepository(map: map)
        let store = makeStore(repository)
        defer { store.shutdown() }
        store.join(pin: "012345", memberName: "대원")
        await waitForJoin(store)
        XCTAssertEqual(store.phase, .setup)
        XCTAssertFalse(store.isSetupFromCamera)
        XCTAssertEqual(repository.joinCount, 1)
    }

    func testInvalidWorldMapStopsJoinInsteadOfSilentlyUsingManualMode() async throws {
        let map = try BundledTrainingMapLoader.load()
        let reference = WorldMapReference(worldMapID: UUID(), setupSHA256: "invalid", floorPlan: map.reference)
        let repository = PositioningRepository(map: map, worldMap: reference)
        let store = makeStore(repository)
        defer { store.shutdown() }
        store.join(pin: "012345", memberName: "대원")
        await waitForJoin(store)
        XCTAssertEqual(store.phase, .join)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(repository.joinCount, 0)
    }

    private func makeFixture() throws -> (store: MemberStore, pose: ARPose) {
        let map = try BundledTrainingMapLoader.load()
        let repository = PositioningRepository(map: map)
        let store = makeStore(repository)
        store.enterDemoSession(session: repository.session, memberName: "테스트")
        store.configurePositioning(setup: PositioningTestData.setup(map))
        return (store, ARPose(x: 0, y: 1.5, z: 0, forwardX: 1, forwardZ: 0))
    }

    private func makeStore(_ repository: PositioningRepository) -> MemberStore {
        MemberStore(sessionRepository: repository, memberRepository: repository,
                    floorPlanFileRepository: repository, recordingRepository: repository,
                    videoChunkRepository: repository, trackResultRepository: repository,
                    worldMapFileRepository: repository, relocalizationTimeout: .milliseconds(30))
    }

    private func waitForJoin(_ store: MemberStore) async {
        for _ in 0..<100 where store.isJoining {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.isJoining)
    }
}

@MainActor
enum PositioningTestData {
    static func freePixel(_ map: TrainingMap) -> MapPoint {
        let grid = map.navigation.grid
        let index = grid.blocked.indices.first {
            grid.blocked[$0] == 0 && (Double($0 % grid.columns) + 0.5) * grid.cellSize + 20 < Double(map.manifest.imageWidth)
        }!
        return MapPoint(x: (Double(index % grid.columns) + 0.5) * grid.cellSize,
                        y: (Double(index / grid.columns) + 0.5) * grid.cellSize)
    }

    static func alignment(_ map: TrainingMap) -> WorldMapAlignment {
        let p = freePixel(map)
        return WorldMapAlignment(rotationDegrees: 0, pixelsPerMeter: 20,
                                 translation: ImagePoint(x: p.x, y: p.y), rmsErrorMeters: 0, algorithmVersion: "test")
    }

    static func setup(_ map: TrainingMap) -> WorldMapSetup {
        WorldMapSetup(schemaVersion: 1, worldMapID: UUID(), createdAt: .now, floorPlan: map.reference,
                      start: WorldMapStart(pose: ARPose(x: 0, y: 1, z: 0, forwardX: 1, forwardZ: 0),
                                           planPoint: NormalizedPoint(x: 0.5, y: 0.5),
                                           directionPoint: NormalizedPoint(x: 0.6, y: 0.5)),
                      correspondences: [], alignment: alignment(map), compression: .none,
                      worldMapSHA256: "test", worldMapBytes: 0)
    }
}

private final class PositioningRepository: SessionRepository, MemberRepository, FloorPlanFileRepository,
    WorldMapFileRepository, RecordingRepository, VideoChunkRepository, TrackResultRepository, @unchecked Sendable {
    let session: Session
    private let lock = NSLock()
    private var joins = 0
    var joinCount: Int { lock.withLock { joins } }
    init(map: TrainingMap, worldMap: WorldMapReference? = nil) {
        session = Session(id: UUID(), pin: "012345", name: "테스트", status: .waiting, floorPlan: map.reference, worldMap: worldMap)
    }
    func createSession(_ session: Session) async throws {}
    func session(forPin pin: String) async throws -> Session { session }
    func updateStatus(of session: Session, to status: SessionStatus) async throws {}
    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { $0.yield(session) }
    }
    func join(_ member: Member, pin: String) async throws { lock.withLock { joins += 1 } }
    func updateReadiness(of member: Member) async throws {}
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> { AsyncThrowingStream { $0.finish() } }
    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}
    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        func data(_ name: String, _ ext: String) throws -> Data {
            let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "TrainingMap")
                ?? Bundle.main.url(forResource: name, withExtension: ext)
            return try Data(contentsOf: XCTUnwrap(url))
        }
        return try FloorPlanFiles(imagePNG: data("training-map", "pngdata"),
                                  navigationMapJSON: data("training-navigation", "json"), resolvedMask: data("training-mask", "bin"))
    }
    func upload(_ files: WorldMapFiles, for reference: WorldMapReference) async throws {}
    func download(_ reference: WorldMapReference) async throws -> WorldMapFiles {
        WorldMapFiles(worldMapArchive: Data(), setupJSON: Data("invalid".utf8))
    }
    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {}
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> { AsyncThrowingStream { $0.finish() } }
    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {}
    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] { [] }
    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {}
    func upload(_ result: TrackResultDocument) async throws {}
    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument { throw RepositoryError.notFound }
}
