import SwiftUI

struct HomeView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            choicesLayout {
                choiceCard(
                    title: "도면 정보 관리",
                    description: "훈련에 사용할 도면을 확인하고 추가합니다.",
                    systemImage: "map",
                    accessibilityIdentifier: "home.floorPlans",
                    action: store.openFloorPlanList
                )

                choiceCard(
                    title: "훈련 세션 생성",
                    description: "도면을 선택하고 팀의 훈련을 준비합니다.",
                    systemImage: "person.3",
                    accessibilityIdentifier: "home.createSession",
                    action: store.openSessionCreation
                )
            }
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .defaultScrollAnchor(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var choicesLayout: AnyLayout {
        horizontalSizeClass == .compact
            ? AnyLayout(VStackLayout(spacing: 24))
            : AnyLayout(HStackLayout(spacing: 24))
    }

    private func choiceCard(
        title: String,
        description: String,
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GroupBox {
                VStack(spacing: 24) {
                    Image(systemName: systemImage)
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text(description)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(description)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

#Preview {
    HomeView()
        .environment(InstructorStore())
}
