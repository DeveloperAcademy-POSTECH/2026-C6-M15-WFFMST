import CQBCore
import Foundation

/// 쇼케이스 부스에서 일반 모드 이전 기록으로 보여줄 훈련 세션 (#252, 머지하지 않는 브랜치).
/// `Resources/PrivateDemo/`(gitignore)에 `scripts/export-showcase-session.py`로 만든 파일이 있을 때만 쓴다.
/// 세션마다 `ShowcaseSession-<sessionID>.json` 하나를 두며, 파일이 없으면 쇼케이스 세션 없이 동작한다.
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
    let floorPlanName: String
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
            floorPlanName: floorPlanName,
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

    /// 쇼케이스 도면 파일. 세션마다 도면이 달라 이름에 도면 ID를 붙인다.
    static func floorPlanResource(_ reference: FloorPlanReference, _ name: String) -> URL? {
        resource("ShowcaseFloorPlan-\(reference.floorPlanID.uuidString)-\(name)")
    }

    /// 쇼케이스 세션 도면 이미지. 기록 썸네일에 쓴다.
    static func floorPlanImageData(for reference: FloorPlanReference) -> Data? {
        guard ShowcaseSessions.bundled.contains(floorPlan: reference),
              let url = floorPlanResource(reference, "original.png") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 번들에 든 쇼케이스 세션 전부. 시작 시각 최신순
    static func loadAll() -> [ShowcaseSession] {
        var urls: [URL] = []
        for bundle in [Bundle.main, Bundle(for: BundleToken.self)] {
            urls += (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("ShowcaseSession-") }
        }
        var seen = Set<UUID>()
        return urls
            .compactMap { url -> ShowcaseSession? in
                guard let data = try? Data(contentsOf: url),
                      let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
                return ShowcaseSession(manifest: manifest)
            }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.startedAt > $1.startedAt }
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
        let floorPlanName: String?
        let startedAt: Double
        let endedAt: Double
        let floorPlan: Plan
        let members: [Entry]
    }

    private init(manifest: Manifest) {
        id = manifest.sessionID
        name = manifest.name
        floorPlanName = manifest.floorPlanName ?? ""
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

/// 번들에 든 쇼케이스 세션 묶음. 비어 있으면 아래 저장소들은 모두 `fallback`으로 넘긴다.
nonisolated struct ShowcaseSessions: Sendable {
    let all: [ShowcaseSession]

    static let bundled = ShowcaseSessions(all: ShowcaseSession.loadAll())

    var ids: Set<UUID> { Set(all.map(\.id)) }

    func session(id: UUID) -> ShowcaseSession? {
        all.first { $0.id == id }
    }

    func participant(for identity: TrackIdentity) -> ShowcaseSession.Participant? {
        session(id: identity.sessionID)?.participant(for: identity)
    }

    func contains(floorPlan reference: FloorPlanReference) -> Bool {
        all.contains { $0.floorPlan == reference }
    }

    /// 번들 영상을 바꿔 다시 설치해도 예전 사본을 쓰지 않도록, 앱을 켤 때 쇼케이스 영상 캐시를 지운다.
    func clearVideoCache(root: URL = AARVideoLoader.defaultCacheRoot) {
        for participant in all.flatMap(\.participants) {
            try? FileManager.default.removeItem(
                at: root.appendingPathComponent(participant.recordingID.uuidString, isDirectory: true)
            )
        }
    }
}

// MARK: - 번들에서 읽는 저장소

/// 쇼케이스 세션 도면은 번들에서, 그 밖의 도면은 `fallback`에서 받는다.
nonisolated struct ShowcaseFloorPlanFileRepository: FloorPlanFileRepository {
    let showcase: ShowcaseSessions
    let fallback: any FloorPlanFileRepository

    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {
        try await fallback.upload(files, for: reference)
    }

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        guard showcase.contains(floorPlan: reference) else { return try await fallback.download(reference) }
        guard let image = ShowcaseSession.floorPlanResource(reference, "original.png"),
              let map = ShowcaseSession.floorPlanResource(reference, "navigation-map.json"),
              let mask = ShowcaseSession.floorPlanResource(reference, "resolved-mask.bin") else {
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
    let showcase: ShowcaseSessions
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
    let showcase: ShowcaseSessions
    let fallback: any AARSoundCandidateLoading
    private let real = RepositoryAARSoundCandidateLoader(repository: ShowcaseSoundCandidateRepository())

    init(showcase: ShowcaseSessions, fallback: any AARSoundCandidateLoading) {
        self.showcase = showcase
        self.fallback = fallback
    }

    func candidates(for identity: TrackIdentity) async throws -> [AARSoundCandidate] {
        guard showcase.participant(for: identity) != nil else { return try await fallback.candidates(for: identity) }
        return try await real.candidates(for: identity)
    }
}

nonisolated struct ShowcaseVideoChunkRepository: VideoChunkRepository {
    let showcase: ShowcaseSessions
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
    let showcase: ShowcaseSessions
    let fallback: any SessionRepository

    func createSession(_ session: Session) async throws { try await fallback.createSession(session) }
    func session(forPin pin: String) async throws -> Session { try await fallback.session(forPin: pin) }

    func updateStatus(of session: Session, to status: SessionStatus) async throws {
        guard showcase.session(id: session.id) == nil else { return }
        try await fallback.updateStatus(of: session, to: status)
    }

    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        guard let session = showcase.session(id: id)?.session else { return fallback.observeSession(id: id) }
        return AsyncThrowingStream { $0.yield(session) }
    }
}

nonisolated struct ShowcaseMemberRepository: MemberRepository {
    let showcase: ShowcaseSessions
    let fallback: any MemberRepository

    func join(_ member: Member, pin: String) async throws { try await fallback.join(member, pin: pin) }
    func updateReadiness(of member: Member) async throws { try await fallback.updateReadiness(of: member) }

    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        guard let members = showcase.session(id: sessionID)?.members() else {
            return fallback.observeMembers(sessionID: sessionID)
        }
        return AsyncThrowingStream { $0.yield(members) }
    }
}

nonisolated struct ShowcaseRecordingRepository: RecordingRepository {
    let showcase: ShowcaseSessions
    let fallback: any RecordingRepository

    func startRecording(_ recording: Recording) async throws { try await fallback.startRecording(recording) }
    func updateRecording(_ recording: Recording) async throws { try await fallback.updateRecording(recording) }

    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        guard let recordings = showcase.session(id: sessionID)?.recordings() else {
            return fallback.observeRecordings(sessionID: sessionID)
        }
        return AsyncThrowingStream { $0.yield(recordings) }
    }
}

/// 이전 훈련 기록에 쇼케이스 세션을 넣는다. 처음에는 고정해 두며(`AppContainer`), 기기 저장소에는 쓰지 않는다.
/// 고정을 풀고 지우면 이번 실행 동안만 목록에서 빠지고, 다음 실행 때 다시 보인다.
@MainActor
final class ShowcaseTrainingHistoryRepository: TrainingHistoryRepository {
    private let showcase: ShowcaseSessions
    private let base: any TrainingHistoryRepository
    private var hiddenIDs: Set<UUID> = []

    init(showcase: ShowcaseSessions, base: any TrainingHistoryRepository) {
        self.showcase = showcase
        self.base = base
    }

    func fetchAll() throws -> [TrainingHistoryRecord] {
        let ids = showcase.ids
        let records = try base.fetchAll().filter { !ids.contains($0.sessionID) }
        let showcaseRecords = showcase.all.filter { !hiddenIDs.contains($0.id) }.map(\.historyRecord)
        return (showcaseRecords + records).sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ record: TrainingHistoryRecord) throws {
        guard !showcase.ids.contains(record.sessionID) else { return }
        try base.save(record)
    }

    func delete(sessionID: UUID) throws {
        guard !showcase.ids.contains(sessionID) else {
            hiddenIDs.insert(sessionID)
            return
        }
        try base.delete(sessionID: sessionID)
    }
}
