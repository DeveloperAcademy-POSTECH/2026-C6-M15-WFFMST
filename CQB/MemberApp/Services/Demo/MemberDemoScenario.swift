import CQBCore
import Foundation
import Observation

/// TestFlight 심사자가 iPad, PIN, 네트워크 없이 MemberApp의 준비·기록 시작 흐름을 확인하는 로컬 시나리오다.
/// 모든 Repository는 앱 내부 메모리 구현이며 Firebase와 Storage 구현을 참조하지 않는다.
enum MemberDemoScenario {
    private static let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000087")!
    private static let floorPlanID = UUID(uuidString: "CF650000-0013-4000-8000-000000000001")!
    private static let navigationSHA256 = "a36e39a0fd35d09a92c39b9e0a747fd1b90d0b0b521aeb16b7e07a71740cbbca"

    @MainActor
    struct Environment {
        let store: MemberStore
        let session: Session
        let control: MemberDemoSessionControl

        func enter() {
            store.enterDemoSession(session: session, memberName: "데모 대원")
        }
    }

    @MainActor
    static func makeEnvironment(
        runID: UUID = UUID(),
        uploadSimulator: MemberDemoUploadSimulator = MemberDemoUploadSimulator()
    ) -> Environment {
        let session = Session(
            id: sessionID,
            pin: "012345",
            name: "TestFlight 데모 훈련",
            status: .waiting,
            floorPlan: FloorPlanReference(
                floorPlanID: floorPlanID,
                navigationSHA256: navigationSHA256
            )
        )
        let sessionRepository = MemberDemoSessionRepository(session: session)
        let store = MemberStore(
            sessionRepository: sessionRepository,
            memberRepository: MemberDemoMemberRepository(),
            floorPlanFileRepository: MemberDemoFloorPlanFileRepository(),
            recordingRepository: MemberDemoRecordingRepository(),
            videoChunkRepository: MemberDemoVideoChunkRepository(),
            trackResultRepository: MemberDemoTrackResultRepository(),
            executionEnvironment: .demo(runID: runID),
            demoUploadSimulator: uploadSimulator
        )
        return Environment(
            store: store,
            session: session,
            control: MemberDemoSessionControl(session: session, repository: sessionRepository)
        )
    }
}

@MainActor
@Observable
final class MemberDemoSessionControl {
    private let session: Session
    private let repository: MemberDemoSessionRepository

    private(set) var isStarting = false
    private(set) var hasStarted = false
    private(set) var errorMessage: String?

    fileprivate init(session: Session, repository: MemberDemoSessionRepository) {
        self.session = session
        self.repository = repository
    }

    func startTraining() async {
        guard !isStarting, !hasStarted else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }
        do {
            try await repository.updateStatus(of: session, to: .running)
            hasStarted = true
        } catch {
            errorMessage = "데모 훈련을 시작하지 못했습니다. 다시 시도해주세요."
        }
    }

    func clearError() {
        errorMessage = nil
    }
}

private final class MemberDemoSessionRepository: SessionRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var session: Session
    private var observers: [UUID: AsyncThrowingStream<Session, Error>.Continuation] = [:]

    init(session: Session) {
        self.session = session
    }

    func createSession(_ session: Session) async throws {
        lock.withLock { self.session = session }
        notify(session)
    }

    func session(forPin pin: String) async throws -> Session {
        let current = lock.withLock { session }
        guard current.pin == pin else { throw RepositoryError.notFound }
        return current
    }

    func updateStatus(of session: Session, to status: SessionStatus) async throws {
        let updated = try lock.withLock { () throws -> Session in
            let current = self.session
            guard Self.rank(status) >= Self.rank(current.status) else {
                throw RepositoryError.invalidStatusChange
            }
            guard status != current.status else { return current }
            let next = Session(
                id: current.id,
                pin: current.pin,
                name: current.name,
                status: status,
                startedAt: status == .running ? current.startedAt ?? .now : current.startedAt,
                floorPlan: current.floorPlan
            )
            self.session = next
            return next
        }
        notify(updated)
    }

    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { continuation in
            let token = UUID()
            let current = lock.withLock { () -> Session? in
                guard session.id == id else { return nil }
                observers[token] = continuation
                return session
            }
            if let current { continuation.yield(current) }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.observers[token] = nil }
            }
        }
    }

    private func notify(_ session: Session) {
        let continuations = lock.withLock { Array(observers.values) }
        continuations.forEach { $0.yield(session) }
    }

    private static func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .preparing: 0
        case .waiting: 1
        case .running: 2
        case .ended: 3
        }
    }
}

private struct MemberDemoMemberRepository: MemberRepository {
    func join(_ member: Member, pin: String) async throws {}
    func updateReadiness(of member: Member) async throws {}
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
}

private struct MemberDemoFloorPlanFileRepository: FloorPlanFileRepository {
    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {
        throw RepositoryError.invalidStatusChange
    }

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        throw RepositoryError.notFound
    }
}

private struct MemberDemoRecordingRepository: RecordingRepository {
    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {}
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
}

private struct MemberDemoVideoChunkRepository: VideoChunkRepository {
    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {}
    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] {
        throw RepositoryError.notFound
    }
    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {}
}

private struct MemberDemoTrackResultRepository: TrackResultRepository {
    func upload(_ result: TrackResultDocument) async throws {}
    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument {
        throw RepositoryError.notFound
    }
}
