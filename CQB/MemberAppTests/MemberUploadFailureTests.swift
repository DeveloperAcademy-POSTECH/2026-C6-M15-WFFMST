import CQBCore
import Foundation
import XCTest
@testable import MemberApp

@MainActor
final class MemberUploadFailureTests: XCTestCase {
    func testRetryDoesNotStartWhileFailureFinalizationIsPending() async throws {
        let recordingRepository = DelayedFailureRecordingRepository()
        let videoRepository = UploadCountingVideoRepository()
        let trackRepository = UploadCountingTrackRepository()
        let store = MemberStore(
            sessionRepository: UploadTestSessionRepository(),
            memberRepository: UploadTestMemberRepository(),
            floorPlanFileRepository: UploadTestFloorPlanRepository(),
            recordingRepository: recordingRepository,
            videoChunkRepository: videoRepository,
            trackResultRepository: trackRepository
        )
        let identity = TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID())
        let fileStore = LocalRecordingFileStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MemberUploadFailureTests-\(UUID().uuidString)", isDirectory: true)
        )
        let files = try fileStore.makeFiles(recordingID: identity.recordingID)
        addTeardownBlock { try? FileManager.default.removeItem(at: files.directory.deletingLastPathComponent()) }
        let chunkURL = files.videoChunk(index: 0)
        try Data("video".utf8).write(to: chunkURL)
        let floorPlan = FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "floor-plan")
        let correction = RouteCorrectionOutput(
            document: TrackResultDocument(
                identity: identity,
                floorPlan: floorPlan,
                sourceRawSHA256: "raw",
                algorithm: TrackAlgorithmIdentity(name: "test", version: "1", settingsID: "test"),
                status: .failed,
                vertices: [],
                sampleCoverage: [],
                unresolvedIntervals: [],
                searchIncomplete: false,
                warnings: [],
                failureReason: .insufficientMovement
            ),
            diagnostics: nil
        )

        try await store.prepareUploadFailureRaceTest(
            identity: identity,
            correction: correction,
            files: files,
            chunkURL: chunkURL
        )
        let initialVideoUploadCount = await videoRepository.uploadCount
        XCTAssertEqual(initialVideoUploadCount, 1)

        let abandon = Task { await store.abandonUploading() }
        await recordingRepository.waitUntilFailureUpdateIsPending()
        XCTAssertTrue(store.isFinalizingUploadFailure)

        await store.retryUploading()

        XCTAssertFalse(store.isUploading)
        XCTAssertFalse(store.isUploadComplete)
        let trackUploadCountWhilePending = await trackRepository.uploadCount
        let statesWhilePending = await recordingRepository.states
        let videoUploadCountWhilePending = await videoRepository.uploadCount
        XCTAssertEqual(trackUploadCountWhilePending, 0)
        XCTAssertEqual(statesWhilePending, [.failed])
        XCTAssertEqual(videoUploadCountWhilePending, 1)

        await recordingRepository.completeFailureUpdate()
        await abandon.value

        XCTAssertTrue(store.isUploadAbandoned)
        XCTAssertFalse(store.isUploadComplete)
        let finalStates = await recordingRepository.states
        XCTAssertEqual(finalStates, [.failed])
    }
}

private actor DelayedFailureRecordingRepository: RecordingRepository {
    private(set) var states: [RecordingState] = []
    private var failureUpdatePending = false
    private var failureContinuation: CheckedContinuation<Void, Never>?
    private var pendingWaiters: [CheckedContinuation<Void, Never>] = []

    func startRecording(_ recording: Recording) async throws {}

    func updateRecording(_ recording: Recording) async throws {
        states.append(recording.state)
        guard recording.state == .failed else { return }
        failureUpdatePending = true
        let waiters = pendingWaiters
        pendingWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { failureContinuation = $0 }
    }

    func waitUntilFailureUpdateIsPending() async {
        if failureUpdatePending { return }
        await withCheckedContinuation { pendingWaiters.append($0) }
    }

    func completeFailureUpdate() {
        failureContinuation?.resume()
        failureContinuation = nil
    }

    nonisolated func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private actor UploadCountingVideoRepository: VideoChunkRepository {
    private(set) var uploadCount = 0

    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {
        uploadCount += 1
    }

    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] {
        throw RepositoryError.notFound
    }

    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {}
}

private actor UploadCountingTrackRepository: TrackResultRepository {
    private(set) var uploadCount = 0

    func upload(_ result: TrackResultDocument) async throws {
        uploadCount += 1
    }

    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument {
        throw RepositoryError.notFound
    }
}

private struct UploadTestSessionRepository: SessionRepository {
    func createSession(_ session: Session) async throws {}
    func session(forPin pin: String) async throws -> Session { throw RepositoryError.notFound }
    func updateStatus(of session: Session, to status: SessionStatus) async throws {}
    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct UploadTestMemberRepository: MemberRepository {
    func join(_ member: Member, pin: String) async throws {}
    func updateReadiness(of member: Member) async throws {}
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct UploadTestFloorPlanRepository: FloorPlanFileRepository {
    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}
    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        throw RepositoryError.notFound
    }
}
