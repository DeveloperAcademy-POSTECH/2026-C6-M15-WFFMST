import CQBCore
import XCTest
@testable import MemberApp

@MainActor
final class MemberDemoScenarioTests: XCTestCase {
    func testDemoModeCreatesANewRunWhenRestarted() {
        let mode = MemberDemoMode()
        let initialRunID = mode.runID

        mode.start()
        let firstRunID = mode.runID
        mode.stop()
        mode.start()

        XCTAssertNotEqual(firstRunID, initialRunID)
        XCTAssertNotEqual(mode.runID, firstRunID)
        XCTAssertTrue(mode.isActive)
    }

    func testDemoScenarioLoadsBundledMapAndReachesWaiting() throws {
        let environment = MemberDemoScenario.makeEnvironment()
        let store = environment.store

        environment.enter()

        XCTAssertEqual(store.phase, .setup)
        XCTAssertEqual(store.pin, "012345")
        XCTAssertEqual(store.memberName, "데모 대원")
        let points = try freePoints(in: XCTUnwrap(store.trainingMap))

        store.confirmPosition(start: points.start, direction: points.direction)

        XCTAssertEqual(store.phase, .waiting)
        XCTAssertEqual(store.startPoint, points.start)
        XCTAssertEqual(store.directionPoint, points.direction)
        store.shutdown()
    }

    func testDemoStartSignalArrivesWithoutAnExternalInstructor() async throws {
        let environment = MemberDemoScenario.makeEnvironment()
        let store = environment.store
        environment.enter()
        let points = try freePoints(in: XCTUnwrap(store.trainingMap))
        store.confirmPosition(start: points.start, direction: points.direction)

        await environment.control.startTraining()
        let receivedSignal = await waitUntil { store.isWaitingForTrainingStart }

        XCTAssertTrue(receivedSignal)
        XCTAssertTrue(environment.control.hasStarted)
        XCTAssertEqual(store.phase, .waiting, "AR 준비가 끝날 때까지 실제 녹화 시작은 대기해야 합니다.")
        store.shutdown()
    }

    func testEachDemoEnvironmentStartsFromJoinState() throws {
        let first = MemberDemoScenario.makeEnvironment()
        first.enter()
        let points = try freePoints(in: XCTUnwrap(first.store.trainingMap))
        first.store.confirmPosition(start: points.start, direction: points.direction)
        XCTAssertEqual(first.store.phase, .waiting)

        let restarted = MemberDemoScenario.makeEnvironment()

        XCTAssertEqual(restarted.store.phase, .join)
        XCTAssertNil(restarted.store.trainingMap)
        XCTAssertTrue(restarted.store.pin.isEmpty)
        XCTAssertTrue(restarted.store.memberName.isEmpty)
        first.store.shutdown()
        restarted.store.shutdown()
    }

    func testDemoEntryDoesNotWriteSessionOrMemberRepositories() async throws {
        let map = try BundledTrainingMapLoader.load()
        let session = Session(
            id: UUID(),
            pin: "012345",
            name: "Repository 격리 테스트",
            status: .waiting,
            floorPlan: map.reference
        )
        let spy = RemoteSessionMemberRepositorySpy(session: session)
        let store = MemberStore(
            sessionRepository: spy,
            memberRepository: spy,
            floorPlanFileRepository: TestFloorPlanFileRepository(),
            recordingRepository: TestRecordingRepository(),
            videoChunkRepository: TestVideoChunkRepository(),
            trackResultRepository: TestTrackResultRepository()
        )

        store.enterDemoSession(session: session, memberName: "데모 대원")
        let points = try freePoints(in: XCTUnwrap(store.trainingMap))
        store.confirmPosition(start: points.start, direction: points.direction)
        store.updateTrackingReadiness(true)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(spy.sessionLookupCount, 0)
        XCTAssertEqual(spy.sessionCreateCount, 0)
        XCTAssertEqual(spy.sessionStatusUpdateCount, 0)
        XCTAssertEqual(spy.memberJoinCount, 0)
        XCTAssertEqual(spy.memberReadinessUpdateCount, 0)
        store.shutdown()
    }

    private func freePoints(in map: TrainingMap) throws -> (start: CGPoint, direction: CGPoint) {
        let grid = map.navigation.grid
        for y in 0..<grid.rows {
            for x in 0..<grid.columns where grid.blocked[y * grid.columns + x] == 0 {
                let startPixel = CGPoint(
                    x: (Double(x) + 0.5) * grid.cellSize,
                    y: (Double(y) + 0.5) * grid.cellSize
                )
                let directionOffset = 10.0
                let directionX = startPixel.x + directionOffset <= Double(map.manifest.imageWidth)
                    ? startPixel.x + directionOffset
                    : startPixel.x - directionOffset
                let directionPixel = CGPoint(
                    x: directionX,
                    y: startPixel.y
                )
                guard directionPixel.x >= 0,
                      hypot(directionPixel.x - startPixel.x, directionPixel.y - startPixel.y) >= 10 else {
                    continue
                }
                return (
                    CGPoint(x: startPixel.x / Double(map.manifest.imageWidth),
                            y: startPixel.y / Double(map.manifest.imageHeight)),
                    CGPoint(x: directionPixel.x / Double(map.manifest.imageWidth),
                            y: directionPixel.y / Double(map.manifest.imageHeight))
                )
            }
        }
        throw TestFailure.noFreePoints
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

    private enum TestFailure: Error {
        case noFreePoints
    }
}

private final class RemoteSessionMemberRepositorySpy: SessionRepository, MemberRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let session: Session
    private var counts = Counts()

    private struct Counts {
        var sessionLookup = 0
        var sessionCreate = 0
        var sessionStatusUpdate = 0
        var memberJoin = 0
        var memberReadinessUpdate = 0
    }

    init(session: Session) {
        self.session = session
    }

    var sessionLookupCount: Int { lock.withLock { counts.sessionLookup } }
    var sessionCreateCount: Int { lock.withLock { counts.sessionCreate } }
    var sessionStatusUpdateCount: Int { lock.withLock { counts.sessionStatusUpdate } }
    var memberJoinCount: Int { lock.withLock { counts.memberJoin } }
    var memberReadinessUpdateCount: Int { lock.withLock { counts.memberReadinessUpdate } }

    func createSession(_ session: Session) async throws {
        lock.withLock { counts.sessionCreate += 1 }
    }

    func session(forPin pin: String) async throws -> Session {
        lock.withLock { counts.sessionLookup += 1 }
        return session
    }

    func updateStatus(of session: Session, to status: SessionStatus) async throws {
        lock.withLock { counts.sessionStatusUpdate += 1 }
    }

    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(session)
            continuation.finish()
        }
    }

    func join(_ member: Member, pin: String) async throws {
        lock.withLock { counts.memberJoin += 1 }
    }

    func updateReadiness(of member: Member) async throws {
        lock.withLock { counts.memberReadinessUpdate += 1 }
    }

    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }
}

private struct TestFloorPlanFileRepository: FloorPlanFileRepository {
    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}
    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        throw RepositoryError.notFound
    }
}

private struct TestRecordingRepository: RecordingRepository {
    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {}
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }
}

private struct TestVideoChunkRepository: VideoChunkRepository {
    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {}
    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] {
        throw RepositoryError.notFound
    }
    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {}
}

private struct TestTrackResultRepository: TrackResultRepository {
    func upload(_ result: TrackResultDocument) async throws {}
    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument {
        throw RepositoryError.notFound
    }
}
