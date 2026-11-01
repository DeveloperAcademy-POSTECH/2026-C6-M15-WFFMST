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

            Text("도면 관리")
                .font(DSTypography.h1)
                .foregroundStyle(InstructorColor.textPrimary)
                .frame(height: 48, alignment: .leading)
                .padding(.bottom, 16)

            Text("등록된 도면을 확인하고 마스크를 수정하거나 목록에서 삭제할 수 있습니다.")
                .font(DSTypography.body)
                .foregroundStyle(InstructorColor.textSecondary)
                .frame(height: 24, alignment: .leading)
                .padding(.bottom, 48)

            floorPlanHeader
                .padding(.bottom, 24)

            catalogContent
        }
        .padding(.top, 32)
        .padding(.horizontal, 48)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var catalogContent: some View {
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
            catalogStatus(title: "등록된 도면이 없습니다.", systemImage: "map")
                .accessibilityIdentifier("floorPlan.catalog.empty")
        } else {
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(store.floorPlans.enumerated()), id: \.element.id) { index, floorPlan in
                            floorPlanRow(floorPlan, number: index + 1)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                previewPanel
                    .frame(width: 440)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var floorPlanHeader: some View {
        HStack(spacing: 24) {
            Text("등록된 도면  \(store.floorPlans.count)개")
            Spacer()
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(InstructorColor.surfaceBase)
            .clipShape(.rect(cornerRadius: 4))
    }

    private func floorPlanRow(_ floorPlan: InstructorFloorPlan, number: Int) -> some View {
        let isSelected = store.previewedFloorPlanID == floorPlan.id
        return HStack(spacing: 12) {
            Button {
                store.selectFloorPlanPreview(floorPlan.id)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(floorPlan.name)
                            .font(DSTypography.h2)
                            .foregroundStyle(InstructorColor.textPrimary)
                            .lineLimit(1)

                        Text(String(format: "도면 %02d", number))
                            .font(DSTypography.bodySmall)
                            .foregroundStyle(InstructorColor.textSecondary)
                    }

                    Text(floorPlan.fileName)
                        .font(DSTypography.body)
                        .foregroundStyle(InstructorColor.textSecondary)
                        .lineLimit(1)

                    Text("축척 설정 완료 · 기준 거리 \(floorPlan.referenceDistance, format: .number) m")
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(InstructorColor.actionPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(floorPlan.name) 미리보기")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("floorPlan.preview.select.\(floorPlan.id)")

            ActionButton("상세보기", tone: .secondary, density: .compact) {
                store.openFloorPlanDetail(floorPlan.id)
            }
            .frame(width: 112, height: 44)
            .accessibilityIdentifier("floorPlan.detail.\(floorPlan.id)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(isSelected ? InstructorColor.surfaceRaised : InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelected ? InstructorColor.actionPrimary : InstructorColor.borderDefault,
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .accessibilityElement(children: .contain)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("도면 미리보기")
                .font(DSTypography.h3)
                .foregroundStyle(InstructorColor.textPrimary)

            Group {
                switch store.floorPlanListPreviewState {
                case .idle:
                    previewStatus("미리볼 도면을 선택해주세요.", systemImage: "map")
                        .accessibilityIdentifier("floorPlan.preview.idle")
                case .loading:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("도면과 최종 마스크를 불러오는 중입니다.")
                    }
                    .foregroundStyle(InstructorColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("floorPlan.preview.loading")
                case .failed(let message):
                    VStack(spacing: 20) {
                        previewStatus(message, systemImage: "exclamationmark.triangle")
                        ActionButton("다시 불러오기", action: store.retryFloorPlanListPreview)
                            .frame(width: 180, height: 48)
                    }
                    .accessibilityIdentifier("floorPlan.preview.error")
                case .loaded:
                    loadedPreview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(InstructorColor.canvas)
            .clipShape(.rect(cornerRadius: 4))

            if let floorPlan = store.previewedFloorPlan {
                VStack(alignment: .leading, spacing: 8) {
                    Text(floorPlan.name)
                        .font(DSTypography.h2)
                        .foregroundStyle(InstructorColor.textPrimary)
                        .lineLimit(1)
                    Text("최종 수정 \(formattedUpdatedAt(floorPlan.updatedAt))")
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(InstructorColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("floorPlan.preview.metadata")
            }
        }
        .padding(20)
        .background(InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var loadedPreview: some View {
        if let image = store.floorPlanListPreviewImage,
           let mask = store.floorPlanListPreviewMaskImage {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                Image(uiImage: mask)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
            .padding(16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("선택한 도면과 최종 마스크 미리보기")
            .accessibilityIdentifier("floorPlan.preview.image")
        } else {
            previewStatus("도면 미리보기를 표시할 수 없습니다.", systemImage: "map")
        }
    }

    private func previewStatus(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .foregroundStyle(InstructorColor.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedUpdatedAt(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year().month(.twoDigits).day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                .locale(Locale(identifier: "ko_KR@hours=h23"))
        )
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
