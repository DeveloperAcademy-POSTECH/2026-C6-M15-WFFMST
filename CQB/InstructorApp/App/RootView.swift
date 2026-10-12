import SwiftUI

struct RootView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        NavigationStack {
            destination
                .navigationTitle(store.phase.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if store.canGoBack && !usesHiFiChrome {
                        ToolbarItem(placement: .topBarLeading) {
                            InstructorBackButton(action: store.goBack)
                        }
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !usesHiFiChrome {
                        Text("로컬 데모 · 등록 도면 파일만 Storage 저장 · 도면 목록과 훈련 진행은 앱 종료 시 사라집니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(.thinMaterial)
                    }
                }
        }
    }

    private var usesHiFiChrome: Bool {
        [
            .home,
            .floorPlanList,
            .floorPlanCreation,
            .sessionCreation,
            .teamReadiness,
            .trainingInProgress,
            .aar,
            .aarCompleted
        ].contains(store.phase)
    }

    @ViewBuilder
    private var destination: some View {
        switch store.phase {
        case .home: HomeView()
        case .floorPlanList: FloorPlanListView()
        case .floorPlanCreation: FloorPlanCreateView()
        case .sessionCreation: TrainingSessionCreateView()
        case .teamReadiness: TeamReadinessView()
        case .trainingInProgress: TrainingInProgressView()
        case .aar: AARView()
        case .aarCompleted: AARCompletedView()
        }
    }
}

#Preview {
    AppContainer()
}
