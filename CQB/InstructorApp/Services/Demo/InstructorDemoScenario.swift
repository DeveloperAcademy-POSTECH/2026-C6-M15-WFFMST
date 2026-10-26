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
    static func makeStore() -> InstructorStore {
        let plan = makeFloorPlan()
        let store = InstructorStore(
            floorPlans: [plan],
            floorPlanFileRepository: DemoFloorPlanFileRepository(),
            floorPlanCatalogRepository: DemoFloorPlanCatalogRepository(floorPlans: [plan]),
            sessionRepository: InstructorDemoSessionRepository(),
            memberRepository: InstructorDemoMemberRepository(memberIDs: memberIDs),
            recordingRepository: InstructorDemoRecordingRepository(memberIDs: memberIDs),
            pinGenerator: { "012345" }
        )
        store.setTrainingName("TestFlight 데모 훈련")
        store.selectFloorPlan(plan.id)
        return store
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

private struct InstructorDemoRecordingRepository: RecordingRepository {
    let memberIDs: [UUID]

    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {}

    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        let recordings = memberIDs.enumerated().map { index, memberID in
            Recording(
                identity: TrackIdentity(
                    sessionID: sessionID,
                    memberID: memberID,
                    recordingID: UUID(uuidString: "30000000-0000-0000-0000-00000000008\(index + 1)")!
                ),
                state: .finishing,
                startedAt: .now,
                lastActiveAt: .now,
                videoChunkCount: nil
            )
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(recordings)
        }
    }
}
