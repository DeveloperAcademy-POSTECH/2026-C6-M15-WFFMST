import SwiftUI

struct HomeView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            choicesLayout {
                GroupBox {
                    VStack(spacing: 24) {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .accessibilityHidden(true)
                        Text("훈련에 사용할 도면을 확인하고 추가합니다.")
                            .foregroundStyle(.secondary)
                        ActionButton("도면 정보 관리", action: store.openFloorPlanList)
                            .accessibilityIdentifier("home.floorPlans")
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding()
                }

                GroupBox {
                    VStack(spacing: 24) {
                        Image(systemName: "person.3")
                            .font(.largeTitle)
                            .accessibilityHidden(true)
                        Text("도면을 선택하고 팀의 훈련을 준비합니다.")
                            .foregroundStyle(.secondary)
                        ActionButton("훈련 세션 생성", action: store.openSessionCreation)
                            .accessibilityIdentifier("home.createSession")
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding()
                }
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
}

#Preview {
    HomeView()
        .environment(InstructorStore())
}
