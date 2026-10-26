import CQBCore
import Foundation
import UIKit

/// TestFlight 심사자가 별도 기기와 서버 데이터 없이 훈련 흐름을 확인할 때 사용하는 앱 내부 시나리오다.
/// 운영 Firebase·SwiftData와 공유하는 상태가 없으며 새 Store를 만들 때마다 초기 상태로 돌아간다.
enum InstructorDemoScenario {
    private static let floorPlanID = UUID(uuidString: "10000000-0000-0000-0000-000000000080")!
    private static let memberIDs = [
        UUID(uuidString: "20000000-0000-0000-0000-000000000081")!,
        UUID(uuidString: "20000000-0000-0000-0000-000000000082")!,
        UUID(uuidString: "20000000-0000-0000-0000-000000000083")!
    ]

    @MainActor
    struct Environment {
        let store: InstructorStore
        let aarStore: AARStore
    }

    @MainActor
    static func makeEnvironment(processingDelay: Duration = .seconds(1)) -> Environment {
        let plan = makeFloorPlan()
        let sessionRepository = InstructorDemoSessionRepository()
        let memberRepository = InstructorDemoMemberRepository(memberIDs: memberIDs)
        let recordingRepository = InstructorDemoRecordingRepository(
            memberIDs: memberIDs,
            sessionRepository: sessionRepository,
            processingDelay: processingDelay
        )
        let store = InstructorStore(
            floorPlans: [plan],
            floorPlanFileRepository: DemoFloorPlanFileRepository(),
            floorPlanCatalogRepository: DemoFloorPlanCatalogRepository(floorPlans: [plan]),
            sessionRepository: sessionRepository,
            memberRepository: memberRepository,
            recordingRepository: recordingRepository,
            pinGenerator: { "012345" }
        )
        store.setTrainingName("TestFlight 데모 훈련")
        store.selectFloorPlan(plan.id)
        let aarStore = AARStore(
            sessionRepository: sessionRepository,
            memberRepository: memberRepository,
            recordingRepository: recordingRepository,
            trackResultRepository: InstructorDemoTrackResultRepository(
                memberIDs: memberIDs,
                floorPlan: plan.reference
            ),
            floorPlanFileRepository: DemoFloorPlanFileRepository(),
            videoChunkRepository: InstructorDemoVideoChunkRepository()
        )
        return Environment(store: store, aarStore: aarStore)
    }

    @MainActor
    static func makeStore() -> InstructorStore {
        makeEnvironment().store
    }

    @MainActor
    private static func makeFloorPlan() -> InstructorFloorPlan {
        let registeredPlan = makeRegisteredFloorPlan()
        return InstructorFloorPlan(
            id: registeredPlan.id.uuidString,
            name: "데모 훈련장",
            fileName: registeredPlan.image.fileName,
            referenceDistance: registeredPlan.scale.meters,
            reference: FloorPlanReference(
                floorPlanID: floorPlanID,
                navigationSHA256: "instructor-demo-plan-v1"
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            registeredPlan: registeredPlan
        )
    }

    @MainActor
    private static func makeRegisteredFloorPlan() -> LocalRegisteredFloorPlan {
        let width = 1_200
        let height = 800
        let cellSize = 20
        let columns = width / cellSize
        let rows = height / cellSize
        var blocked = [UInt8](repeating: 0, count: columns * rows)

        func block(_ x: Int, _ y: Int) {
            guard (0..<columns).contains(x), (0..<rows).contains(y) else { return }
            blocked[y * columns + x] = 1
        }

        for x in 0..<columns {
            block(x, 0)
            block(x, rows - 1)
        }
        for y in 0..<rows {
            block(0, y)
            block(columns - 1, y)
        }
        for x in 12..<48 where !(27...31).contains(x) { block(x, 13) }
        for x in 8..<38 where !(18...22).contains(x) { block(x, 27) }
        for y in 13..<35 where !(20...24).contains(y) { block(38, y) }

        let grid = LocalObstacleGrid(
            columns: columns,
            rows: rows,
            cellSizePixels: cellSize,
            blocked: blocked
        )
        let image = LocalImportedImage(
            pngData: makeFloorPlanPNG(width: width, height: height),
            width: width,
            height: height,
            fileName: "DEBRIEF-demo-floor-plan.png"
        )
        return LocalRegisteredFloorPlan(
            id: floorPlanID,
            name: "데모 훈련장",
            image: image,
            baseGrid: grid,
            edits: [],
            outline: [
                LocalPlanPoint(x: 0.02, y: 0.03),
                LocalPlanPoint(x: 0.98, y: 0.03),
                LocalPlanPoint(x: 0.98, y: 0.97),
                LocalPlanPoint(x: 0.02, y: 0.97)
            ],
            scale: LocalPlanScale(
                a: LocalPlanPoint(x: 0.1, y: 0.9),
                b: LocalPlanPoint(x: 0.35, y: 0.9),
                meters: 10
            ),
            resolvedGrid: grid
        )
    }

    @MainActor
    private static func makeFloorPlanPNG(width: Int, height: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            UIColor(red: 0.94, green: 0.93, blue: 0.89, alpha: 1).setFill()
            context.fill(bounds)

            let wall = UIBezierPath()
            wall.lineWidth = 18
            UIColor(red: 0.12, green: 0.17, blue: 0.16, alpha: 1).setStroke()
            wall.append(UIBezierPath(rect: bounds.insetBy(dx: 24, dy: 24)))

            wall.move(to: CGPoint(x: 240, y: 270))
            wall.addLine(to: CGPoint(x: 550, y: 270))
            wall.move(to: CGPoint(x: 650, y: 270))
            wall.addLine(to: CGPoint(x: 960, y: 270))

            wall.move(to: CGPoint(x: 160, y: 540))
            wall.addLine(to: CGPoint(x: 390, y: 540))
            wall.move(to: CGPoint(x: 490, y: 540))
            wall.addLine(to: CGPoint(x: 770, y: 540))

            wall.move(to: CGPoint(x: 770, y: 270))
            wall.addLine(to: CGPoint(x: 770, y: 400))
            wall.move(to: CGPoint(x: 770, y: 500))
            wall.addLine(to: CGPoint(x: 770, y: 700))
            wall.stroke()
        }
        return image.pngData() ?? Data()
    }
}

private final class InstructorDemoSessionRepository: SessionRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [UUID: Session] = [:]
    private var observers: [UUID: [UUID: AsyncThrowingStream<Session, Error>.Continuation]] = [:]

    func createSession(_ session: Session) async throws {
        save(session)
    }

    func session(forPin pin: String) async throws -> Session {
        guard let session = session(matching: pin) else { throw RepositoryError.notFound }
        return session
    }

    func updateStatus(of session: Session, to status: SessionStatus) async throws {
        let updated = try update(session: session, status: status)
        notify(updated)
    }

    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { continuation in
            let token = UUID()
            let initial = addObserver(continuation, token: token, sessionID: id)
            if let initial { continuation.yield(initial) }
            continuation.onTermination = { [weak self] _ in
                self?.removeObserver(token: token, sessionID: id)
            }
        }
    }

    func startedAt(sessionID: UUID) -> Date? {
        lock.withLock { sessions[sessionID]?.startedAt }
    }

    private func save(_ session: Session) {
        lock.withLock { sessions[session.id] = session }
    }

    private func session(matching pin: String) -> Session? {
        lock.withLock { sessions.values.first { $0.pin == pin } }
    }

    private func update(session: Session, status: SessionStatus) throws -> Session {
        try lock.withLock {
            let current = sessions[session.id] ?? session
            guard Self.rank(status) >= Self.rank(current.status) else {
                throw RepositoryError.invalidStatusChange
            }
            let startedAt = status == .running ? current.startedAt ?? .now : current.startedAt
            let updated = Session(
                id: current.id,
                pin: current.pin,
                name: current.name,
                status: status,
                startedAt: startedAt,
                floorPlan: current.floorPlan
            )
            sessions[session.id] = updated
            return updated
        }
    }

    private func notify(_ session: Session) {
        let continuations = lock.withLock { Array(observers[session.id, default: [:]].values) }
        continuations.forEach { $0.yield(session) }
    }

    private func addObserver(
        _ continuation: AsyncThrowingStream<Session, Error>.Continuation,
        token: UUID,
        sessionID: UUID
    ) -> Session? {
        lock.withLock {
            observers[sessionID, default: [:]][token] = continuation
            return sessions[sessionID]
        }
    }

    private func removeObserver(token: UUID, sessionID: UUID) {
        lock.withLock { observers[sessionID]?[token] = nil }
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

private struct InstructorDemoMemberRepository: MemberRepository {
    let memberIDs: [UUID]

    func join(_ member: Member, pin: String) async throws {}
    func updateReadiness(of member: Member) async throws {}

    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        let names = ["데모 대원 1", "데모 대원 2", "데모 대원 3"]
        let members = zip(memberIDs, names).map { id, name in
            Member(
                id: id,
                sessionID: sessionID,
                name: name,
                isReady: true,
                lastActiveAt: .now
            )
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(members)
        }
    }
}

private final class InstructorDemoRecordingRepository: RecordingRepository, @unchecked Sendable {
    let memberIDs: [UUID]
    let sessionRepository: InstructorDemoSessionRepository
    let processingDelay: Duration
    private let lock = NSLock()
    private var recordings: [UUID: [Recording]] = [:]
    private var scheduledSessions: Set<UUID> = []
    private var observers: [UUID: [UUID: AsyncThrowingStream<[Recording], Error>.Continuation]] = [:]

    init(
        memberIDs: [UUID],
        sessionRepository: InstructorDemoSessionRepository,
        processingDelay: Duration
    ) {
        self.memberIDs = memberIDs
        self.sessionRepository = sessionRepository
        self.processingDelay = processingDelay
    }

    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {}

    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        return AsyncThrowingStream { continuation in
            let token = UUID()
            let (current, shouldSchedule) = lock.withLock { () -> ([Recording], Bool) in
                let current = recordings[sessionID] ?? makeRecordings(sessionID: sessionID, state: .finishing)
                recordings[sessionID] = current
                observers[sessionID, default: [:]][token] = continuation
                return (current, scheduledSessions.insert(sessionID).inserted)
            }
            continuation.yield(current)
            if shouldSchedule { scheduleCompletion(sessionID: sessionID) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.observers[sessionID]?[token] = nil }
            }
        }
    }

    private func scheduleCompletion(sessionID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: processingDelay)
            let completed = makeRecordings(sessionID: sessionID, state: .done)
            let continuations = lock.withLock { () -> [AsyncThrowingStream<[Recording], Error>.Continuation] in
                self.recordings[sessionID] = completed
                return Array(self.observers[sessionID, default: [:]].values)
            }
            continuations.forEach { $0.yield(completed) }
        }
    }

    private func makeRecordings(sessionID: UUID, state: RecordingState) -> [Recording] {
        let startedAt = sessionRepository.startedAt(sessionID: sessionID) ?? .now
        return memberIDs.enumerated().map { index, memberID in
            Recording(
                identity: TrackIdentity(
                    sessionID: sessionID,
                    memberID: memberID,
                    recordingID: UUID(uuidString: "30000000-0000-0000-0000-00000000008\(index + 1)")!
                ),
                state: state,
                startedAt: startedAt,
                lastActiveAt: .now,
                videoChunkCount: state == .done ? 1 : nil
            )
        }
    }
}

private struct InstructorDemoTrackResultRepository: TrackResultRepository {
    let memberIDs: [UUID]
    let floorPlan: FloorPlanReference

    func upload(_ result: TrackResultDocument) async throws {}

    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument {
        guard let index = memberIDs.firstIndex(of: identity.memberID) else {
            throw RepositoryError.notFound
        }
        let points = Self.paths[index]
        let vertices = points.enumerated().map { offset, point in
            TrackResultVertex(
                t: Double(offset) * 1.5,
                point: point,
                part: 0,
                sampleIndex: offset,
                provenance: .generated
            )
        }
        return TrackResultDocument(
            identity: identity,
            floorPlan: floorPlan,
            sourceRawSHA256: "instructor-demo-track-\(index + 1)",
            algorithm: TrackAlgorithmIdentity(
                name: "instructor-demo",
                version: "1",
                settingsID: "testflight-review"
            ),
            status: .done,
            vertices: vertices,
            sampleCoverage: [
                TrackSampleCoverage(
                    samples: TrackSampleRange(from: 0, through: vertices.count - 1),
                    vertices: TrackVertexRange(from: 0, through: vertices.count - 1)
                )
            ],
            unresolvedIntervals: [],
            searchIncomplete: false,
            warnings: []
        )
    }

    private static let paths: [[ImagePoint]] = [
        [
            ImagePoint(x: 110, y: 650), ImagePoint(x: 250, y: 650),
            ImagePoint(x: 430, y: 620), ImagePoint(x: 450, y: 480),
            ImagePoint(x: 450, y: 360), ImagePoint(x: 600, y: 330),
            ImagePoint(x: 720, y: 360), ImagePoint(x: 720, y: 470),
            ImagePoint(x: 900, y: 500)
        ],
        [
            ImagePoint(x: 1050, y: 650), ImagePoint(x: 900, y: 650),
            ImagePoint(x: 820, y: 570), ImagePoint(x: 820, y: 450),
            ImagePoint(x: 870, y: 350), ImagePoint(x: 960, y: 220),
            ImagePoint(x: 780, y: 170), ImagePoint(x: 620, y: 180),
            ImagePoint(x: 580, y: 310)
        ],
        [
            ImagePoint(x: 120, y: 150), ImagePoint(x: 260, y: 180),
            ImagePoint(x: 410, y: 190), ImagePoint(x: 560, y: 210),
            ImagePoint(x: 610, y: 330), ImagePoint(x: 570, y: 460),
            ImagePoint(x: 500, y: 600), ImagePoint(x: 680, y: 650),
            ImagePoint(x: 880, y: 640)
        ]
    ]
}

private final class InstructorDemoBundleToken {}

private struct InstructorDemoVideoChunkRepository: VideoChunkRepository {
    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {}

    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] {
        guard chunkCount == 1,
              let source = [Bundle.main, Bundle(for: InstructorDemoBundleToken.self)]
                .compactMap({ $0.url(forResource: "DEBRIEF-Demo-AAR", withExtension: "mp4") })
                .first else {
            throw RepositoryError.notFound
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("chunk_0000.mp4")
        try FileManager.default.copyItem(at: source, to: destination)
        return [destination]
    }

    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {}
}
