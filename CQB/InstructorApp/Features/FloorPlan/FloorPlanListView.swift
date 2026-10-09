import SwiftUI

struct FloorPlanListView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("훈련 세션을 만들 때 등록된 도면 중 하나를 선택합니다.")
                .foregroundStyle(.secondary)

            HStack {
                Text("등록된 도면 \(store.floorPlans.count)개")
                    .font(.headline)
                Spacer()
                ActionButton("도면 추가", systemImage: "plus", action: store.openFloorPlanCreation)
                    .accessibilityIdentifier("floorPlan.add")
            }

            ScrollView {
                LazyVStack(spacing: 16) {
                    if store.floorPlans.isEmpty {
                        ContentUnavailableView(
                            "등록된 도면이 없습니다",
                            systemImage: "map",
                            description: Text("도면 추가를 눌러 이미지와 장애물, 축척을 등록해보세요.")
                        )
                    }

                    ForEach(store.floorPlans) { floorPlan in
                        floorPlanRow(floorPlan)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func floorPlanRow(_ floorPlan: DemoFloorPlan) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(floorPlan.name)
                        .font(.title3.bold())
                    Text(floorPlan.registeredPlan == nil ? "샘플 도면" : "로컬 등록 · 앱 실행 중 유지")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(floorPlan.fileName)
                    Text("기준 거리 \(floorPlan.referenceDistance, format: .number) m\(floorPlan.registeredPlan == nil ? " · 샘플 값" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 16)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("등록된 도면") {
    FloorPlanListView()
        .environment(InstructorStore())
}

#Preview("빈 목록") {
    FloorPlanListView()
        .environment(InstructorStore(floorPlans: []))
}
