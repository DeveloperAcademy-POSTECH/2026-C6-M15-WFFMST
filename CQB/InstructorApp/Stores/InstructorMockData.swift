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

struct DemoParticipant: Identifiable, Equatable {
    let id: String
    let number: Int
    let name: String
    var isReady: Bool
    let x: Double
    let y: Double
    var displayName: String { "대원 \(number)" }
}

enum ReadinessSample: String, CaseIterable, Identifiable {
    case ready, partial, empty
    var id: Self { self }
    var title: String {
        switch self {
        case .ready: "전원 준비"
        case .partial: "일부 준비"
        case .empty: "참가자 없음"
        }
    }
}

enum InstructorMockData {
    static let participants = ["유키", "매버릭", "도넛", "새미", "엘리", "노을"]
        .enumerated().map { index, name in
            DemoParticipant(id: "member-\(index + 1)", number: index + 1, name: name,
                            isReady: true, x: 0.22 + Double(index % 4) * 0.17,
                            y: index < 4 ? 0.5 : 0.68)
        }
}

/// Preview와 로컬 Store 검사에서 서버 없이 등록 완료 흐름을 실행한다.
struct DemoFloorPlanFileRepository: FloorPlanFileRepository {
    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        throw RepositoryError.notFound
    }
}
