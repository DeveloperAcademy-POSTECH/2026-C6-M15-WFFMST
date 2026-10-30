import CQBCore
import Foundation

struct InstructorParticipant: Identifiable, Equatable {
    let id: String
    let number: Int
    let name: String
    var isReady: Bool
    let x: Double
    let y: Double
    var displayName: String { "대원 \(number)" }
}

/// Preview와 로컬 검증에서만 쓰는 화면 Fixture다.
enum InstructorPreviewFixture {
    static let participants = ["유키", "매버릭", "도넛", "새미", "엘리", "노을"]
        .enumerated().map { index, name in
            InstructorParticipant(
                id: "member-\(index + 1)",
                number: index + 1,
                name: name,
                isReady: true,
                x: 0.22 + Double(index % 4) * 0.17,
                y: index < 4 ? 0.5 : 0.68
            )
        }

    static func session(floorPlan: FloorPlanReference, pin: String = "012345") -> Session {
        Session(
            id: UUID(),
            pin: pin,
            name: "미리보기 훈련",
            status: .waiting,
            floorPlan: floorPlan
        )
    }

    @MainActor
    static func store(
        floorPlan: InstructorFloorPlan,
        participants: [InstructorParticipant]? = nil,
        phase: InstructorPhase = .teamReadiness
    ) -> InstructorStore {
        InstructorStore(
            floorPlans: [floorPlan],
            previewSession: session(floorPlan: floorPlan.reference),
            previewParticipants: participants ?? Self.participants,
            previewPhase: phase
        )
    }
}

/// Preview와 로컬 Store 검사에서 서버 없이 등록 완료 흐름을 실행한다.
struct DemoFloorPlanFileRepository: FloorPlanFileRepository {
    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        throw RepositoryError.notFound
    }
}

/// Preview와 로컬 Store 검사에서 사용하는 메모리 카탈로그다.
@MainActor
final class DemoFloorPlanCatalogRepository: FloorPlanCatalogRepository {
    private var stored: [InstructorFloorPlan]
    var fetchError: Error?
    var saveError: Error?
    var deleteError: Error?

    init(floorPlans: [InstructorFloorPlan] = []) {
        stored = floorPlans
    }

    func fetchAll() throws -> [InstructorFloorPlan] {
        if let fetchError { throw fetchError }
        return stored
    }

    func save(_ floorPlan: InstructorFloorPlan) throws {
        if let saveError { throw saveError }
        if let index = stored.firstIndex(where: { $0.id == floorPlan.id }) {
            stored[index] = floorPlan
        } else {
            stored.append(floorPlan)
        }
    }

    func delete(id: String) throws {
        if let deleteError { throw deleteError }
        stored.removeAll { $0.id == id }
    }
}

/// Preview에서 Firebase 없이 Store를 생성하기 위한 빈 Repository다.
struct DemoSessionRepository: SessionRepository {
    func createSession(_ session: Session) async throws {}
    func session(forPin pin: String) async throws -> Session { throw RepositoryError.notFound }
    func updateStatus(of session: Session, to status: SessionStatus) async throws {}
    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// Preview에서 Firebase 없이 Store를 생성하기 위한 빈 Repository다.
struct DemoMemberRepository: MemberRepository {
    func join(_ member: Member, pin: String) async throws {}
    func updateReadiness(of member: Member) async throws {}
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
}

struct DemoRecordingRepository: RecordingRepository {
    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {}
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        AsyncThrowingStream { $0.yield([]); $0.finish() }
    }
}
