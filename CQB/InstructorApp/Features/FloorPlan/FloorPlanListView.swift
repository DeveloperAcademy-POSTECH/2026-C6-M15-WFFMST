import CQBDesignSystem
import SwiftUI

struct FloorPlanListView: View {
    private static let addActionFont: Font = {
        DSFonts.register()
        return .custom("NotoSansKR-Medium", size: 16, relativeTo: .body)
    }()

    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InstructorBackButton(action: store.goBack)
                .padding(.bottom, 4)

            Text("훈련 도면")
                .font(DSTypography.h1)
                .foregroundStyle(InstructorColor.textPrimary)
                .frame(height: 48, alignment: .leading)
                .padding(.bottom, 16)

            Text("훈련 세션을 만들 때 등록된 도면 중 하나를 선택합니다.")
                .font(DSTypography.body)
                .foregroundStyle(InstructorColor.textSecondary)
                .frame(height: 24, alignment: .leading)
                .padding(.bottom, 72)

            ScrollView {
                LazyVStack(spacing: 24) {
                    floorPlanHeader

                    if store.isLoadingFloorPlans {
                        catalogStatus(
                            title: "등록한 도면을 불러오는 중입니다.",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .accessibilityIdentifier("floorPlan.catalog.loading")
                    } else if let error = store.floorPlanCatalogError {
                        VStack(spacing: 20) {
                            catalogStatus(title: error, systemImage: "exclamationmark.triangle")
                            ActionButton("다시 불러오기", action: store.retryFloorPlanCatalogLoad)
                                .frame(width: 220, height: 52)
                                .accessibilityIdentifier("floorPlan.catalog.retry")
                        }
                        .accessibilityIdentifier("floorPlan.catalog.error")
                    } else if store.floorPlans.isEmpty {
                        catalogStatus(
                            title: "등록된 도면이 없습니다.",
                            systemImage: "map"
                        )
                        .accessibilityIdentifier("floorPlan.catalog.empty")
                    } else {
                        ForEach(Array(store.floorPlans.enumerated()), id: \.element.id) { index, floorPlan in
                            floorPlanRow(floorPlan, number: index + 1)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 32)
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var floorPlanHeader: some View {
        HStack(spacing: 24) {
            Text("등록된 도면  \(store.floorPlans.count)개")
                .frame(width: 470, alignment: .leading)

            Text("파일 · 축척 상태")
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: store.openFloorPlanCreation) {
                Text("+")
                    .font(Self.addActionFont)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(width: 56, height: 44)
            .background(InstructorColor.borderDefault)
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
            }
            .accessibilityLabel("도면 추가")
            .accessibilityIdentifier("floorPlan.add")
            .disabled(store.floorPlanCatalogState != .loaded)
        }
        .font(DSTypography.h3)
        .foregroundStyle(InstructorColor.textPrimary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
        .background(InstructorColor.surfaceRaised)
        .clipShape(.rect(cornerRadius: 4))
    }

    private func catalogStatus(title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .foregroundStyle(InstructorColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(InstructorColor.surfaceBase)
            .clipShape(.rect(cornerRadius: 4))
    }

    private func floorPlanRow(_ floorPlan: InstructorFloorPlan, number: Int) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(floorPlan.name)
                    .font(DSTypography.h2)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .frame(height: 36, alignment: .leading)

                Text(String(format: "도면 %02d", number))
                    .font(DSTypography.bodySmall)
                    .foregroundStyle(InstructorColor.textSecondary)
                    .frame(height: 21, alignment: .leading)
            }
            .frame(width: 470, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text(floorPlan.fileName)
                    .font(DSTypography.body)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .frame(height: 24, alignment: .leading)

                Text(floorPlan.registeredPlan == nil
                    ? "축척 설정 완료 · 기준 거리 \(floorPlan.referenceDistance, format: .number) m"
                    : "Storage 업로드 완료 · 기준 거리 \(floorPlan.referenceDistance, format: .number) m")
                    .font(DSTypography.bodySmall)
                    .foregroundStyle(InstructorColor.actionPrimary)
                    .frame(height: 21, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, minHeight: 128, maxHeight: 128, alignment: .topLeading)
        .background(InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

}

#Preview("등록된 도면") {
    NavigationStack {
        FloorPlanListView()
            .environment(InstructorStore(floorPlans: [
                InstructorFloorPlan(
                    id: "preview-plan",
                    name: "훈련장 A",
                    fileName: "훈련장 A 도면.png",
                    referenceDistance: 15
                )
            ]))
    }
    .frame(width: 1_366, height: 1_024)
    .preferredColorScheme(.dark)
}

#Preview("빈 목록") {
    NavigationStack {
        FloorPlanListView()
            .environment(InstructorStore())
    }
    .frame(width: 1_366, height: 1_024)
    .preferredColorScheme(.dark)
}
