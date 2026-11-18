import CQBCore
import Foundation

/// 쇼케이스 부스에서 데모 모드로 보여줄 실제 훈련 세션 (#252, 머지하지 않는 브랜치).
/// `Resources/PrivateDemo/`(gitignore)에 `scripts/export-showcase-session.py`로 만든 파일이 있을 때만 쓴다.
/// 파일이 없으면 `load()`가 nil이고 데모 모드는 기존 가짜 데이터로 동작한다.
nonisolated struct ShowcaseSession: Sendable {
    struct Participant: Sendable {
        let memberID: UUID
        let recordingID: UUID
        let name: String
        let startedAt: Date
        let videoChunkCount: Int
    }

    let id: UUID
    let name: String
    let startedAt: Date
    let endedAt: Date
    let floorPlan: FloorPlanReference
    let participants: [Participant]

    var session: Session {
        Session(id: id, pin: "000000", name: name, status: .ended, startedAt: startedAt, floorPlan: floorPlan)
    }

    var historyRecord: TrainingHistoryRecord {
        TrainingHistoryRecord(
            sessionID: id,
            trainingName: name,
            floorPlan: floorPlan,
            floorPlanName: "선박 도면",
            participantNames: participants.map(\.name),
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    func members() -> [Member] {
        participants.map {
            Member(id: $0.memberID, sessionID: id, name: $0.name, isReady: true, lastActiveAt: endedAt)
        }
    }

    func recordings() -> [Recording] {
        participants.map {
            Recording(
                identity: identity(of: $0),
                state: .done,
                startedAt: $0.startedAt,
                lastActiveAt: endedAt,
                videoChunkCount: $0.videoChunkCount
            )
        }
    }

    func identity(of participant: Participant) -> TrackIdentity {
        TrackIdentity(sessionID: id, memberID: participant.memberID, recordingID: participant.recordingID)
    }

    func participant(for identity: TrackIdentity) -> Participant? {
        guard identity.sessionID == id else { return nil }
        return participants.first { $0.recordingID == identity.recordingID }
    }

    // MARK: - 번들 파일

    private final class BundleToken {}

    static func resource(_ name: String) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for bundle in [Bundle.main, Bundle(for: BundleToken.self)] {
            if let url = bundle.url(forResource: base, withExtension: ext) { return url }
        }
        return nil
    }

    /// 앱 번들에 든 쇼케이스 세션. 파일이 없으면 nil
    static let bundled: ShowcaseSession? = load()

    /// 쇼케이스 세션 도면 이미지. 기록 썸네일에 쓴다.
    static func floorPlanImageData(for reference: FloorPlanReference) -> Data? {
        guard reference == bundled?.floorPlan,
              let url = resource("ShowcaseFloorPlan-original.png") else { return nil }
        return try? Data(contentsOf: url)
    }

    static func load() -> ShowcaseSession? {
        guard let url = resource("ShowcaseSession.json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        return ShowcaseSession(manifest: manifest)
    }

    private struct Manifest: Decodable {
        struct Plan: Decodable {
            let floorPlanID: UUID
            let navigationSHA256: String
        }

        struct Entry: Decodable {
            let memberID: UUID
            let recordingID: UUID
            let name: String
            let startedAt: Double
            let videoChunkCount: Int
        }

        let sessionID: UUID
        let name: String
        let startedAt: Double
        let endedAt: Double
        let floorPlan: Plan
        let members: [Entry]
    }

    private init(manifest: Manifest) {
        id = manifest.sessionID
        name = manifest.name
        startedAt = Date(timeIntervalSince1970: manifest.startedAt)
        endedAt = Date(timeIntervalSince1970: manifest.endedAt)
        floorPlan = FloorPlanReference(
            floorPlanID: manifest.floorPlan.floorPlanID,
            navigationSHA256: manifest.floorPlan.navigationSHA256
        )
        participants = manifest.members.map {
            Participant(
                memberID: $0.memberID,
                recordingID: $0.recordingID,
                name: $0.name,
                startedAt: Date(timeIntervalSince1970: $0.startedAt),
                videoChunkCount: $0.videoChunkCount
            )
        }
    }
}

// MARK: - 번들에서 읽는 저장소

/// 쇼케이스 세션 도면은 번들에서, 그 밖의 도면은 `fallback`에서 받는다.
nonisolated struct ShowcaseFloorPlanFileRepository: FloorPlanFileRepository {
    let showcase: ShowcaseSession
    let fallback: any FloorPlanFileRepository

    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {
        try await fallback.upload(files, for: reference)
    }

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        guard reference == showcase.floorPlan else { return try await fallback.download(reference) }
        guard let image = ShowcaseSession.resource("ShowcaseFloorPlan-original.png"),
              let map = ShowcaseSession.resource("ShowcaseFloorPlan-navigation-map.json"),
              let mask = ShowcaseSession.resource("ShowcaseFloorPlan-resolved-mask.bin") else {
            throw RepositoryError.notFound
        }
        return FloorPlanFiles(
            imagePNG: try Data(contentsOf: image),
            navigationMapJSON: try Data(contentsOf: map),
            resolvedMask: try Data(contentsOf: mask)
        )
    }
}

nonisolated struct ShowcaseTrackResultRepository: TrackResultRepository {
    let showcase: ShowcaseSession
    let fallback: any TrackResultRepository

    func upload(_ result: TrackResultDocument) async throws {
        try await fallback.upload(result)
    }

    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument {
        guard showcase.participant(for: identity) != nil else { return try await fallback.download(identity) }
        guard let url = ShowcaseSession.resource("Showcase-\(identity.recordingID.uuidString)-result.json") else {
            throw RepositoryError.notFound
        }
        return try JSONDecoder().decode(TrackResultDocument.self, from: Data(contentsOf: url))
    }
}

/// 실제 기록과 같은 판정(`RepositoryAARSoundCandidateLoader`)을 거치도록 문서 단위로 돌려준다.
nonisolated struct ShowcaseSoundCandidateRepository: SoundCandidateRepository {
    func upload(_ document: SoundCandidateDocument) async throws {}

    func download(_ identity: TrackIdentity) async throws -> SoundCandidateDocument {
        guard let url = ShowcaseSession.resource("Showcase-\(identity.recordingID.uuidString)-sound.json") else {
            throw RepositoryError.notFound
        }
        let document = try JSONDecoder().decode(SoundCandidateDocument.self, from: Data(contentsOf: url))
        guard document.identity == identity else { throw RepositoryError.integrityMismatch }
        try document.validate()
        return document
    }
}

nonisolated struct ShowcaseSoundCandidateLoader: AARSoundCandidateLoading {
    let showcase: ShowcaseSession
    let fallback: any AARSoundCandidateLoading
    private let real = RepositoryAARSoundCandidateLoader(repository: ShowcaseSoundCandidateRepository())

    init(showcase: ShowcaseSession, fallback: any AARSoundCandidateLoading) {
        self.showcase = showcase
        self.fallback = fallback
    }

    func candidates(for identity: TrackIdentity) async throws -> [AARSoundCandidate] {
        guard showcase.participant(for: identity) != nil else { return try await fallback.candidates(for: identity) }
        return try await real.candidates(for: identity)
    }
}

nonisolated struct ShowcaseVideoChunkRepository: VideoChunkRepository {
    let showcase: ShowcaseSession
    let fallback: any VideoChunkRepository

    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {
        try await fallback.upload(fileURL: fileURL, identity: identity, index: index)
    }

    /// 쇼케이스 영상은 번들 파일이라 지우지 않는다. 다른 세션은 원래대로 지운다.
    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {
        guard showcase.participant(for: identity) == nil else { return }
        try await fallback.deleteVideo(identity, chunkCount: chunkCount)
    }

    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] {
        guard showcase.participant(for: identity) != nil else {
            return try await fallback.downloadVideo(identity, chunkCount: chunkCount, to: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try (0..<chunkCount).map { index in
            let name = String(format: "chunk_%04d.mp4", index)
            guard let source = ShowcaseSession.resource("Showcase-\(identity.recordingID.uuidString)-\(name)") else {
                throw RepositoryError.notFound
            }
            let destination = directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
    }
}

// MARK: - 일반 모드 연결

/// 일반 모드에서 쇼케이스 세션만 번들에서 돌려주고, 나머지는 Firestore로 보낸다.
/// 쇼케이스 세션은 다른 기기의 교관 계정 것이라 규칙상 서버에서 읽을 수 없다.
nonisolated struct ShowcaseSessionRepository: SessionRepository {
    let showcase: ShowcaseSession
    let fallback: any SessionRepository

    func createSession(_ session: Session) async throws { try await fallback.createSession(session) }
    func session(forPin pin: String) async throws -> Session { try await fallback.session(forPin: pin) }

    func updateStatus(of session: Session, to status: SessionStatus) async throws {
        guard session.id != showcase.id else { return }
        try await fallback.updateStatus(of: session, to: status)
    }

    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        guard id == showcase.id else { return fallback.observeSession(id: id) }
        let session = showcase.session
        return AsyncThrowingStream { $0.yield(session) }
    }
}

nonisolated struct ShowcaseMemberRepository: MemberRepository {
    let showcase: ShowcaseSession
    let fallback: any MemberRepository

    func join(_ member: Member, pin: String) async throws { try await fallback.join(member, pin: pin) }
    func updateReadiness(of member: Member) async throws { try await fallback.updateReadiness(of: member) }

    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        guard sessionID == showcase.id else { return fallback.observeMembers(sessionID: sessionID) }
        let members = showcase.members()
        return AsyncThrowingStream { $0.yield(members) }
    }
}

nonisolated struct ShowcaseRecordingRepository: RecordingRepository {
    let showcase: ShowcaseSession
    let fallback: any RecordingRepository

    func startRecording(_ recording: Recording) async throws { try await fallback.startRecording(recording) }
    func updateRecording(_ recording: Recording) async throws { try await fallback.updateRecording(recording) }

    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        guard sessionID == showcase.id else { return fallback.observeRecordings(sessionID: sessionID) }
        let recordings = showcase.recordings()
        return AsyncThrowingStream { $0.yield(recordings) }
    }
}

/// 이전 훈련 기록에 쇼케이스 세션을 넣는다. 처음에는 고정해 두며(`AppContainer`), 기기 저장소에는 쓰지 않는다.
/// 고정을 풀고 지우면 이번 실행 동안만 목록에서 빠지고, 다음 실행 때 다시 보인다.
@MainActor
final class ShowcaseTrainingHistoryRepository: TrainingHistoryRepository {
    private let showcase: ShowcaseSession
    private let base: any TrainingHistoryRepository

    init(showcase: ShowcaseSession, base: any TrainingHistoryRepository) {
        self.showcase = showcase
        self.base = base
    }

    func fetchAll() throws -> [TrainingHistoryRecord] {
        let records = try base.fetchAll().filter { $0.sessionID != showcase.id }
        return [showcase.historyRecord] + records
    }

    func save(_ record: TrainingHistoryRecord) throws {
        guard record.sessionID != showcase.id else { return }
        try base.save(record)
    }

    func delete(sessionID: UUID) throws {
        guard sessionID != showcase.id else { return }
        try base.delete(sessionID: sessionID)
    }
}
