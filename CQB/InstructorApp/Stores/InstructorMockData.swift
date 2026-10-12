import CQBCore
import Foundation

// InstructorApp 화면 연결 전용 데이터. 공통 모델·서버 계약이 아니다.
struct DemoFloorPlan: Identifiable, Equatable {
    let id: String
    let name: String
    let fileName: String
    let referenceDistance: Double
    let reference: FloorPlanReference
    var registeredPlan: LocalRegisteredFloorPlan? = nil

    init(
        id: String,
        name: String,
        fileName: String,
        referenceDistance: Double,
        reference: FloorPlanReference = FloorPlanReference(
            floorPlanID: UUID(),
            navigationSHA256: "local-demo"
        ),
        registeredPlan: LocalRegisteredFloorPlan? = nil
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.referenceDistance = referenceDistance
        self.reference = reference
        self.registeredPlan = registeredPlan
    }
}

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
        floorPlan: DemoFloorPlan,
        participants: [InstructorParticipant]? = nil
    ) -> InstructorStore {
        InstructorStore(
            floorPlans: [floorPlan],
            previewSession: session(floorPlan: floorPlan.reference),
            previewParticipants: participants ?? Self.participants
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
