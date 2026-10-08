import SwiftUI

struct FloorPlanCreateView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView {
                columnsLayout {
                    settings
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    preview
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 24) {
                Text("추가한 샘플은 앱 실행 중에만 유지됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ActionButton("도면 저장", action: store.saveFloorPlan)
                    .disabled(!store.canSaveFloorPlan)
                    .accessibilityIdentifier("floorPlan.save")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                Text("01  도면 이름")
                    .font(.headline)
                TextField(
                    "도면 이름을 입력하세요",
                    text: Binding(get: { store.floorPlanDraftName }, set: store.setFloorPlanDraftName)
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("도면 이름")
                .accessibilityIdentifier("floorPlan.name")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("02  도면 파일")
                    .font(.headline)
                HStack {
                    Text(store.hasSampleFloorPlan ? "샘플 도면.png" : "선택된 샘플 없음")
                    Spacer()
                    ActionButton("샘플 도면 사용", action: store.useSampleFloorPlan)
                        .accessibilityIdentifier("floorPlan.sample")
                }
                Text("파일 선택은 후속 구현 예정입니다. 샘플을 선택하면 미리보기를 확인할 수 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("03  축척 설정")
                    .font(.headline)
                LabeledContent("A–B 참고 거리", value: store.hasSampleFloorPlan ? "15 m (샘플)" : "샘플 선택 필요")
                Text("기준점 지정과 축척 계산은 후속 구현 예정입니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var preview: some View {
        GroupBox("도면 미리보기") {
            if store.hasSampleFloorPlan {
                FloorPlanPreview(title: "샘플 도면")
                    .frame(minHeight: 400)
            } else {
                ContentUnavailableView(
                    "미리보기 없음",
                    systemImage: "photo",
                    description: Text("샘플 도면을 선택하세요.")
                )
                .frame(minHeight: 400)
            }
        }
    }

    private var columnsLayout: AnyLayout {
        horizontalSizeClass == .compact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 32))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 32))
    }
}

#Preview {
    FloorPlanCreateView()
        .environment(InstructorStore())
}
