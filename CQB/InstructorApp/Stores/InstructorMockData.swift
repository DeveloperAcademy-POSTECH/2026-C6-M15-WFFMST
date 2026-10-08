import Foundation

// InstructorApp 화면 연결 전용 데이터. 공통 모델·서버 계약이 아니다.
struct DemoFloorPlan: Identifiable, Equatable {
    let id: String
    let name: String
    let fileName: String
    let referenceDistance: Double
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
    static let floorPlans = [
        DemoFloorPlan(id: "plan-a", name: "훈련장 A", fileName: "훈련장 A 도면.png", referenceDistance: 15),
        DemoFloorPlan(id: "plan-b", name: "훈련장 B", fileName: "B동 1층.png", referenceDistance: 12)
    ]
    static let participants = ["강유키", "매버릭", "김도넛", "이채미", "곽엘리", "노을"]
        .enumerated().map { index, name in
            DemoParticipant(id: "member-\(index + 1)", number: index + 1, name: name,
                            isReady: true, x: 0.22 + Double(index % 4) * 0.17,
                            y: index < 4 ? 0.5 : 0.68)
        }
}
