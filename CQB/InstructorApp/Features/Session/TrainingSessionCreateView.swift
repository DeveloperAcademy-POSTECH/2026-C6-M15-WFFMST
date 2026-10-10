import SwiftUI

struct TrainingSessionCreateView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 32) {
                    sessionFields
                        .frame(minWidth: 280, maxWidth: .infinity, alignment: .topLeading)
                    planPreview
                        .frame(minWidth: 320, maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 24) {
                    sessionFields
                    planPreview
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                ActionButton("세션 생성", action: store.createSession)
                    .disabled(!store.canCreateSession)
                    .accessibilityIdentifier("session.create")
            }
            .padding(24)
            .background(.bar)
        }
    }

    private var sessionFields: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                Text("훈련명").font(.headline)
                TextField("훈련명을 입력하세요", text: Binding(get: { store.trainingName }, set: store.setTrainingName))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("훈련명")
                    .accessibilityIdentifier("session.name")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("훈련 도면").font(.headline)
                SingleSelectionMenu(
                    title: "훈련 도면",
                    options: store.floorPlans,
                    selection: store.selectedFloorPlanID,
                    optionTitle: \.name,
                    onSelect: store.selectFloorPlan
                )
                .accessibilityIdentifier("session.plan")
                Text("훈련명과 도면을 선택하면 샘플 팀 준비 화면으로 이동합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("도면 미리보기").font(.headline)
            if let plan = store.selectedFloorPlan {
                FloorPlanPreview(title: plan.name, image: store.selectedPlanImage)
                    .frame(minHeight: 360)
            } else {
                ContentUnavailableView("도면을 선택하세요", systemImage: "map", description: Text("선택한 샘플 도면을 여기에 표시합니다."))
                    .frame(minHeight: 360)
            }
            Text("출발점·방향 보정은 이번 화면 연결 데모에 포함되지 않습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    TrainingSessionCreateView()
        .environment(InstructorStore())
}
