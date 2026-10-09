enum InstructorPhase: Equatable {
    case home, floorPlanList, floorPlanCreation, sessionCreation
    case teamReadiness, trainingInProgress, aar, aarCompleted

    var title: String {
        switch self {
        case .home: "Instructor"
        case .floorPlanList: "훈련 도면"
        case .floorPlanCreation: "훈련 도면 설정"
        case .sessionCreation: "새 훈련 세션"
        case .teamReadiness: "팀 준비 상태"
        case .trainingInProgress: "훈련 중"
        case .aar: "AAR"
        case .aarCompleted: "AAR 종료"
        }
    }
}

enum AARMode: Equatable {
    case movement, video
}
