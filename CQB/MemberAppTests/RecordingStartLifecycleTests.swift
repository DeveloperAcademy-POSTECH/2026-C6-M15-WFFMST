import CQBCore
import XCTest
@testable import MemberApp

@MainActor
final class RecordingStartLifecycleTests: XCTestCase {
    func testEndedIsConsumedBeforePermissionResponseAndLateResponseCannotStartRecording() async throws {
        let fixture = try Fixture()
        fixture.feed.send(.running, session: fixture.session)
        await eventually { fixture.starter.waitingForPermission }
        fixture.feed.send(.ended, session: fixture.session)
        await eventually { fixture.store.phase == .join }
        XCTAssertFalse(fixture.store.isStarting)
        fixture.starter.allowPermission()
        await eventually { fixture.starter.cleanupCount == 1 }
        assertCancelled(fixture)
    }

    func testEndedIsConsumedWhileFirstAudioBufferIsPending() async throws {
        let fixture = try Fixture()
        fixture.feed.send(.running, session: fixture.session)
        await eventually { fixture.starter.waitingForPermission }
        fixture.starter.allowPermission()
        await eventually { fixture.starter.waitingForAudio }
        fixture.feed.send(.ended, session: fixture.session)
        await eventually { fixture.store.phase == .join }
        fixture.starter.deliverAudio()
        await eventually { fixture.starter.cleanupCount == 1 }
        assertCancelled(fixture)
    }

    func testSuccessfulCaptureReturningAfterEndedIsCancelledBeforeStoreCommit() async throws {
        let fixture = try Fixture()
        fixture.starter.ignoreFinalValidity = true
        fixture.feed.send(.running, session: fixture.session)
        await eventually { fixture.starter.waitingForPermission }
        fixture.starter.allowPermission()
        await eventually { fixture.starter.waitingForAudio }
        fixture.feed.send(.ended, session: fixture.session)
        await eventually { fixture.store.phase == .join }
        fixture.starter.deliverAudio()
        await eventually { fixture.starter.cleanupCount == 1 }
        XCTAssertEqual(fixture.starter.captureCount, 1, "Exercise the successful-return/ended race.")
        assertCancelled(fixture)
    }

    func testShutdownCancelsPendingStartWithoutShowingRetryError() async throws {
        let fixture = try Fixture()
        fixture.feed.send(.running, session: fixture.session)
        await eventually { fixture.starter.waitingForPermission }
        fixture.store.shutdown()
        fixture.starter.allowPermission()
        await eventually { fixture.starter.cleanupCount == 1 }
        XCTAssertEqual(fixture.store.phase, .waiting)
        XCTAssertFalse(fixture.store.isStarting)
        XCTAssertFalse(fixture.store.canRetryRecordingStart)
        XCTAssertNil(fixture.store.errorMessage)
        XCTAssertFalse(fixture.starter.isCapturing)
        XCTAssertEqual(fixture.feed.metadataCount, 0)
    }

    func testReadinessChangesAndRetryDoNotCreateConcurrentStarts() async throws {
        let fixture = try Fixture(ready: false)
        fixture.feed.send(.running, session: fixture.session)
        await eventually { fixture.store.isWaitingForTrainingStart }
        fixture.store.updateTrackingReadiness(true)
        fixture.store.updateTrackingReadiness(false)
        fixture.store.updateTrackingReadiness(true)
        await fixture.store.retryStartingRecording()
        await eventually { fixture.starter.waitingForPermission }
        XCTAssertEqual(fixture.starter.startCount, 1)
        fixture.starter.allowPermission()
        await eventually { fixture.starter.waitingForAudio }
        fixture.starter.deliverAudio()
        await eventually { fixture.store.phase == .recording && fixture.feed.metadataCount == 1 }
        XCTAssertFalse(fixture.store.isStarting)
        XCTAssertTrue(fixture.starter.isCapturing)
        await fixture.cleanup()
    }

    func testCancelledOldAttemptDoesNotClearNewSessionStart() async throws {
        let fixture = try Fixture()
        fixture.feed.send(.running, session: fixture.session)
        await eventually { fixture.starter.waitingForPermission }
        fixture.feed.send(.ended, session: fixture.session)
        await eventually { fixture.store.phase == .join }
        let nextSession = fixture.newSession()
        try fixture.enter(nextSession)
        fixture.feed.send(.running, session: nextSession)
        await eventually { fixture.store.isWaitingForTrainingStart }
        XCTAssertEqual(fixture.starter.startCount, 1)
        fixture.starter.allowPermission() // Finish cleanup for the cancelled old attempt.
        await eventually { fixture.starter.startCount == 2 && fixture.starter.waitingForPermission }
        XCTAssertTrue(fixture.store.isStarting)
        fixture.starter.allowPermission()
        await eventually { fixture.starter.waitingForAudio }
        fixture.starter.deliverAudio()
        await eventually { fixture.store.phase == .recording && fixture.feed.metadataCount == 1 }
        XCTAssertEqual(fixture.starter.cleanupCount, 1)
        XCTAssertEqual(fixture.starter.captureCount, 1)
        await fixture.cleanup()
    }

    func testCancelledPermissionWaitReturnsBeforeSystemCallback() async {
        let callback = PermissionCallback()
        let task = Task { await ARRecordingService.requestMicrophoneAccess(using: callback.install) }
        await eventually { callback.isInstalled }
        task.cancel()
        let allowed = await task.value
        XCTAssertFalse(allowed)
        callback.respond(true) // The late system response must be harmless.
    }

    func testCancelledStartCleanupPreservesSavedAndOtherRecordings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = LocalRecordingFileStore(baseDirectory: root)
        let pending = try files.makeFiles(recordingID: UUID())
        let saved = try files.makeFiles(recordingID: UUID())
        let other = try files.makeFiles(recordingID: UUID())
        try Data("pending".utf8).write(to: pending.uploadManifest)
        try Data("saved".utf8).write(to: saved.raw)
        try files.discardUncommittedFiles(pending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.directory.path))
        XCTAssertThrowsError(try files.discardUncommittedFiles(saved))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.raw.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.directory.path))
        let foreign = LocalRecordingFiles(directory: root.appendingPathComponent(UUID().uuidString))
        XCTAssertThrowsError(try files.discardUncommittedFiles(foreign))
    }

    private func assertCancelled(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(fixture.store.phase, .join, file: file, line: line)
        XCTAssertFalse(fixture.store.canRetryRecordingStart, file: file, line: line)
        XCTAssertNil(fixture.store.recordingStartedAt, file: file, line: line)
        XCTAssertNil(fixture.store.recordingFiles, file: file, line: line)
        XCTAssertFalse(fixture.starter.isCapturing, file: file, line: line)
        XCTAssertEqual(fixture.feed.metadataCount, 0, file: file, line: line)
        if let directory = fixture.starter.directory {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().path), file: file, line: line)
        }
    }

    private func eventually(file: StaticString = #filePath, line: UInt = #line,
                            _ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for state transition", file: file, line: line)
    }
}

@MainActor
private final class Fixture {
    let feed = SessionFeed()
    let starter = ControlledRecordingStarter()
    let map: TrainingMap
    let store: MemberStore
    let session: Session

    init(ready: Bool = true) throws {
        map = try BundledTrainingMapLoader.load()
        session = Session(id: UUID(), pin: "012345", name: "녹화 시작 취소", status: .waiting, floorPlan: map.reference)
        store = MemberStore(sessionRepository: feed, memberRepository: feed, floorPlanFileRepository: feed,
                            recordingRepository: feed, videoChunkRepository: feed, trackResultRepository: feed,
                            recordingStarter: starter)
        try enter(session, ready: ready)
    }

    func newSession() -> Session {
        Session(id: UUID(), pin: "012345", name: "다음 훈련", status: .waiting, floorPlan: map.reference)
    }

    func enter(_ session: Session, ready: Bool = true) throws {
        store.enterDemoSession(session: session, memberName: "테스트 대원")
        let grid = map.navigation.grid
        let index = try XCTUnwrap(grid.blocked.firstIndex(of: 0))
        let x = (Double(index % grid.columns) + 0.5) * grid.cellSize
        let y = (Double(index / grid.columns) + 0.5) * grid.cellSize
        let dx = x + 10 <= Double(map.manifest.imageWidth) ? 10.0 : -10.0
        store.confirmPosition(start: CGPoint(x: x / Double(map.manifest.imageWidth), y: y / Double(map.manifest.imageHeight)),
                              direction: CGPoint(x: (x + dx) / Double(map.manifest.imageWidth), y: y / Double(map.manifest.imageHeight)))
        XCTAssertEqual(store.phase, .waiting)
        store.updateTrackingReadiness(ready)
    }

    func cleanup() async {
        store.shutdown()
        await starter.cancelUncommittedRecording()
        if let files = store.recordingFiles { try? FileManager.default.removeItem(at: files.directory) }
    }
}

@MainActor
private final class ControlledRecordingStarter: MemberRecordingStarting {
    var startCount = 0
    var cleanupCount = 0
    var captureCount = 0
    var isCapturing = false
    var ignoreFinalValidity = false
    var directory: URL?
    private var permission: CheckedContinuation<Void, Never>?
    private var audio: CheckedContinuation<Void, Never>?
    var waitingForPermission: Bool { permission != nil }
    var waitingForAudio: Bool { audio != nil }

    func startRecording(to directory: URL, start: MapPoint, direction: MapPoint,
                        shouldStart: @escaping @MainActor () -> Bool) async throws {
        self.directory = directory
        startCount += 1
        // Deliberately non-cooperative waits simulate a system dialog or a late callback.
        await withCheckedContinuation { permission = $0 }
        guard !Task.isCancelled, shouldStart() else { throw CancellationError() }
        await withCheckedContinuation { audio = $0 }
        if !ignoreFinalValidity {
            guard !Task.isCancelled, shouldStart() else { throw CancellationError() }
        }
        isCapturing = true
        captureCount += 1
    }

    func allowPermission() { let value = permission; permission = nil; value?.resume() }
    func deliverAudio() { let value = audio; audio = nil; value?.resume() }
    func cancelUncommittedRecording() async { cleanupCount += 1; isCapturing = false }
}

private final class PermissionCallback: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (Bool) -> Void)?
    var isInstalled: Bool { lock.lock(); defer { lock.unlock() }; return callback != nil }
    func install(_ callback: @escaping @Sendable (Bool) -> Void) { lock.lock(); self.callback = callback; lock.unlock() }
    func respond(_ value: Bool) { lock.lock(); let callback = callback; self.callback = nil; lock.unlock(); callback?(value) }
}

private final class SessionFeed: SessionRepository, MemberRepository, FloorPlanFileRepository,
                                 RecordingRepository, VideoChunkRepository, TrackResultRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [UUID: AsyncThrowingStream<Session, Error>.Continuation] = [:]
    private var latest: [UUID: Session] = [:]
    private var recordedMetadata = 0
    var metadataCount: Int { lock.lock(); defer { lock.unlock() }; return recordedMetadata }
    func send(_ status: SessionStatus, session: Session) {
        let update = Session(id: session.id, pin: session.pin, name: session.name, status: status, floorPlan: session.floorPlan)
        lock.lock(); latest[session.id] = update; let continuation = streams[session.id]; lock.unlock()
        continuation?.yield(update)
    }
    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { continuation in
            lock.lock(); streams[id] = continuation; let session = latest[id]; lock.unlock()
            if let session { continuation.yield(session) }
        }
    }
    func createSession(_ session: Session) async throws {}
    func session(forPin pin: String) async throws -> Session { throw RepositoryError.notFound }
    func updateStatus(of session: Session, to status: SessionStatus) async throws { send(status, session: session) }
    func join(_ member: Member, pin: String) async throws {}
    func updateReadiness(of member: Member) async throws {}
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> { AsyncThrowingStream { $0.finish() } }
    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}
    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles { throw RepositoryError.notFound }
    func startRecording(_ recording: Recording) async throws { lock.withLock { recordedMetadata += 1 } }
    func updateRecording(_ recording: Recording) async throws {}
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> { AsyncThrowingStream { $0.finish() } }
    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {}
    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] { [] }
    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {}
    func upload(_ result: TrackResultDocument) async throws {}
    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument { throw RepositoryError.notFound }
}
