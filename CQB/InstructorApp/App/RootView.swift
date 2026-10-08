import SwiftUI

struct RootView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        NavigationStack {
            destination
                .navigationTitle(store.phase.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if store.canGoBack {
                        ToolbarItem(placement: .topBarLeading) {
                            ActionButton("뒤로", systemImage: "chevron.left", action: store.goBack)
                                .accessibilityIdentifier("navigation.back")
                        }
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Text("화면 연결 데모 · 샘플 데이터 · 서버에 저장하거나 훈련 명령을 보내지 않습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                }
        }
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
