import CQBDesignSystem
import SwiftUI

struct FloorPlanListView: View {
    @Environment(InstructorStore.self) private var store

    private let catalogWidthRatio: CGFloat = 465.0 / 1_262.0
    private let minimumCatalogWidth: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navigationBar
                .padding(.horizontal, DSSpacing.s40)
                .padding(.top, DSSpacing.s40)

            Text("도면 관리")
                .dsTextStyle(DSTypography.headingBold36)
                .foregroundStyle(DSColor.contentPrimary)
                .padding(.horizontal, DSSpacing.s40)
                .padding(.top, 100)
                .padding(.bottom, 25)

            catalogContent
                .padding(.horizontal, DSSpacing.s40)
                .padding(.bottom, DSSpacing.s60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            FloorPlanBackButton(action: store.goBack)
                .disabled(!store.canGoBack)

            Spacer()

            Button(action: store.openFloorPlanCreation) {
                Text("새 도면 추가")
                    .padding(.horizontal, DSSpacing.s20)
            }
                .buttonStyle(.dsPrimary)
                .accessibilityIdentifier("floorPlan.add")
                .disabled(store.floorPlanCatalogState != .loaded)
        }
        .frame(height: DSSize.controlHeight)
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
            VStack(spacing: DSSpacing.s20) {
                catalogStatus(title: error, systemImage: "exclamationmark.triangle")
                Button("다시 불러오기", action: store.retryFloorPlanCatalogLoad)
                    .buttonStyle(.dsPrimary)
                    .accessibilityIdentifier("floorPlan.catalog.retry")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("floorPlan.catalog.error")
        } else if store.floorPlans.isEmpty {
            catalogStatus(title: "등록된 도면이 없습니다.", systemImage: "map")
                .accessibilityIdentifier("floorPlan.catalog.empty")
        } else {
            GeometryReader { proxy in
                let distributableWidth = max(0, proxy.size.width - DSSpacing.s24)
                let catalogWidth = max(
                    minimumCatalogWidth,
                    distributableWidth * catalogWidthRatio
                )

                HStack(spacing: DSSpacing.s24) {
                    floorPlanCatalog
                        .frame(width: catalogWidth)

                    previewPanel
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                }
            }
        }
    }

    private var floorPlanCatalog: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s40) {
            Text("등록된 도면")
                .dsTextStyle(DSTypography.headingBold20)
                .foregroundStyle(DSColor.contentPrimary)

            ScrollView {
                LazyVStack(spacing: DSSpacing.s4) {
                    ForEach(store.floorPlans) { floorPlan in
                        floorPlanRow(floorPlan)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(DSSpacing.s12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.surfacePrimary)
        .clipShape(.rect(cornerRadius: DSRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.large)
                .stroke(DSColor.borderPrimary, lineWidth: 1)
        }
    }

    private func floorPlanRow(_ floorPlan: InstructorFloorPlan) -> some View {
        let isSelected = store.previewedFloorPlanID == floorPlan.id

        return Button {
            store.selectFloorPlanPreview(floorPlan.id)
        } label: {
            HStack(spacing: DSSpacing.s32) {
                selectionIndicator(isSelected: isSelected)

                VStack(alignment: .leading, spacing: DSSpacing.s8) {
                    Text(floorPlan.name)
                        .dsTextStyle(DSTypography.headingSemiBold24)
                        .foregroundStyle(isSelected ? DSColor.contentPrimary : DSColor.contentSecondary)
                        .lineLimit(1)

                    Text("생성일 \(formattedCreatedAt(floorPlan.createdAt))")
                        .dsTextStyle(DSTypography.bodyRegular16)
                        .foregroundStyle(isSelected ? DSColor.contentPrimary : DSColor.contentSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 22)
            .padding(.trailing, DSSpacing.s20)
            .padding(.vertical, DSSpacing.s16)
            .frame(maxWidth: .infinity, minHeight: 95, alignment: .leading)
            .background(isSelected ? DSColor.surfaceSelected : DSColor.surfacePrimary)
            .clipShape(.rect(cornerRadius: DSRadius.large))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(floorPlan.name), 생성일 \(formattedCreatedAt(floorPlan.createdAt))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("floorPlan.preview.select.\(floorPlan.id)")
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(
                    isSelected ? DSColor.actionPrimary : InstructorColor.floorPlanSelectionIdle,
                    lineWidth: isSelected ? 2 : 1.5
                )
            if isSelected {
                Circle()
                    .fill(DSColor.actionPrimary)
                    .padding(4)
            }
        }
        .frame(width: DSSpacing.s24, height: DSSpacing.s24)
        .accessibilityHidden(true)
    }

    private var previewPanel: some View {
        ZStack(alignment: .topLeading) {
            DSColor.surfaceSecondary
            previewContent

            Text("도면 미리보기")
                .dsTextStyle(DSTypography.headingBold20)
                .foregroundStyle(DSColor.surfaceSelected)
                .padding(.horizontal, DSSpacing.s8)
                .padding(.vertical, DSSpacing.s4)
                .background(DSColor.contentPrimary.opacity(0.72))
                .clipShape(.rect(cornerRadius: DSRadius.small))
                .padding(DSSpacing.s20)

            if let floorPlan = store.previewedFloorPlan {
                HStack {
                    Spacer()
                    Button("상세보기 및 편집") {
                        store.openFloorPlanDetail(floorPlan.id)
                    }
                    .dsTextStyle(DSTypography.headingSemiBold20)
                    .foregroundStyle(DSColor.contentPrimary)
                    .padding(.horizontal, DSSpacing.s20)
                    .frame(minHeight: DSSize.controlHeight)
                    .background(DSColor.surfacePrimary)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(InstructorColor.floorPlanPreviewActionBorder, lineWidth: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("floorPlan.detail.\(floorPlan.id)")
                }
                .padding(.top, DSSpacing.s12)
                .padding(.trailing, DSSpacing.s12)
            }
        }
        .frame(maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: DSRadius.large))
    }

    @ViewBuilder
    private var previewContent: some View {
        switch store.floorPlanListPreviewState {
        case .idle:
            previewStatus("미리볼 도면을 선택해주세요.", systemImage: "map")
                .accessibilityIdentifier("floorPlan.preview.idle")
        case .loading:
            VStack(spacing: DSSpacing.s16) {
                ProgressView()
                Text("도면을 불러오는 중입니다.")
            }
            .foregroundStyle(DSColor.contentTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("floorPlan.preview.loading")
        case .failed(let message):
            VStack(spacing: DSSpacing.s20) {
                previewStatus(message, systemImage: "exclamationmark.triangle")
                Button("다시 불러오기", action: store.retryFloorPlanListPreview)
                    .buttonStyle(.dsPrimary)
            }
            .padding(DSSpacing.s40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("floorPlan.preview.error")
        case .loaded:
            loadedPreview
        }
    }

    @ViewBuilder
    private var loadedPreview: some View {
        if let image = store.floorPlanListPreviewImage {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("선택한 도면 미리보기")
            .accessibilityIdentifier("floorPlan.preview.image")
        } else {
            previewStatus("도면 미리보기를 표시할 수 없습니다.", systemImage: "map")
        }
    }

    private func catalogStatus(title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .foregroundStyle(DSColor.contentTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSColor.surfacePrimary)
            .clipShape(.rect(cornerRadius: DSRadius.large))
    }

    private func previewStatus(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .foregroundStyle(DSColor.contentTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedCreatedAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

#Preview("등록된 도면") {
    NavigationStack {
        FloorPlanListView()
            .environment(InstructorStore(floorPlans: [
                InstructorFloorPlan(
                    id: "preview-plan",
                    name: "훈련장 A 도면 v1",
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
