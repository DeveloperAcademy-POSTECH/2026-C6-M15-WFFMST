import SwiftUI

struct RootView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(InstructorDemoMode.self) private var demoMode

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
                    if demoMode.isActive {
                        demoBanner
                    } else if !usesHiFiChrome {
                        Text("등록 도면 목록은 기기에 저장 · 훈련 진행은 앱 종료 시 사라집니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(.thinMaterial)
                    }
                }
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 16) {
            Label("데모 모드 · 샘플 데이터", systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(InstructorColor.textPrimary)

            Spacer()

            Button("데모 종료", action: demoMode.stop)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(InstructorColor.actionPrimary)
                .accessibilityIdentifier("demo.exit")
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 44)
        .background(InstructorColor.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(InstructorColor.borderDefault)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("demo.banner")
    }

    private var usesHiFiChrome: Bool {
        [
            .home,
            .floorPlanList,
            .floorPlanDetail,
            .floorPlanCreation,
            .floorPlanEditing,
            .sessionCreation,
            .teamReadiness,
            .trainingInProgress,
            .resultsPreparation,
            .aar,
            .aarCompleted
        ].contains(store.phase)
    }

    @ViewBuilder
    private var destination: some View {
        switch store.phase {
        case .home: HomeView()
        case .floorPlanList: FloorPlanListView()
        case .floorPlanDetail: FloorPlanDetailView()
        case .floorPlanCreation: FloorPlanCreateView()
        case .floorPlanEditing: FloorPlanCreateView()
        case .sessionCreation: TrainingSessionCreateView()
        case .teamReadiness: TeamReadinessView()
        case .trainingInProgress: TrainingInProgressView()
        case .resultsPreparation: TrainingResultsPreparationView()
        case .aar: AARView()
        case .aarCompleted: AARCompletedView()
        }
    }
}

#Preview {
    AppContainer()
}
