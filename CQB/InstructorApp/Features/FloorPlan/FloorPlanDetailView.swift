import CQBDesignSystem
import SwiftUI

struct FloorPlanDetailView: View {
    @Environment(InstructorStore.self) private var store
    @State private var showsDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            previewRegion
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            detailPanel
                .frame(width: 404)
        }
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert(deleteAlertTitle, isPresented: $showsDeleteConfirmation) {
            Button("도면 삭제", role: .destructive, action: store.deleteViewedFloorPlan)
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 도면은 되돌릴 수 없습니다.")
        }
    }

    private var previewRegion: some View {
        ZStack {
            DSColor.backgroundPrimary

            preview
                .frame(maxWidth: 409, maxHeight: 864)
                .padding(.top, 77)
                .padding(.bottom, 83)

            HStack(spacing: DSSpacing.s8) {
                FloorPlanBackButton(action: store.goBack)
                    .disabled(!store.canGoBack)

                Text("훈련 도면")
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(DSColor.contentPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, DSSpacing.s40)
            .padding(.leading, DSSpacing.s40)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch store.floorPlanDetailState {
        case .idle, .loading:
            VStack(spacing: DSSpacing.s16) {
                ProgressView()
                Text("도면과 마스크를 불러오는 중입니다.")
            }
            .foregroundStyle(DSColor.contentTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("floorPlan.detail.loading")
        case .failed(let message):
            VStack(spacing: DSSpacing.s20) {
                ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
                Button("다시 불러오기", action: store.retryFloorPlanDetailLoad)
                    .buttonStyle(.dsPrimary)
            }
            .foregroundStyle(DSColor.contentTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("floorPlan.detail.error")
        case .loaded:
            loadedPreview
        }
    }

    @ViewBuilder
    private var loadedPreview: some View {
        if let image = store.floorPlanDetailImage {
            LocalFloorPlanCanvas(
                image: image,
                mask: store.floorPlanDetailMaskImage,
                tool: .move,
                normalizedDiameter: 0.006,
                layers: FloorPlanLayerDisplay(planOpacity: 1, maskOpacity: 0.55, tint: .red),
                onStroke: { _ in },
                onPoint: { _ in }
            )
            .shadow(color: .white.opacity(0.5), radius: 20)
            .accessibilityLabel("도면과 최종 마스크 미리보기")
            .accessibilityIdentifier("floorPlan.detail.canvas")
        } else {
            ContentUnavailableView("도면 미리보기를 표시할 수 없습니다.", systemImage: "map")
                .foregroundStyle(DSColor.contentTertiary)
        }
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let plan = store.viewedFloorPlan {
                Text(plan.name)
                    .dsTextStyle(DSTypography.headingBold32)
                    .foregroundStyle(DSColor.contentPrimary)
                    .lineLimit(2)
                    .accessibilityIdentifier("floorPlan.detail.name")

                Text("최종 수정 시간")
                    .dsTextStyle(DSTypography.headingSemiBold20)
                    .foregroundStyle(DSColor.contentPrimary)
                    .padding(.top, DSSpacing.s60)

                Text(formattedUpdatedAt(plan.updatedAt))
                    .dsTextStyle(DSTypography.bodyRegular24)
                    .foregroundStyle(DSColor.contentPrimary)
                    .padding(.top, DSSpacing.s4)
                    .accessibilityIdentifier("floorPlan.detail.updatedAt")
            }

            if let error = store.floorPlanDeletionError {
                Text(error)
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(DSColor.statusError)
                    .padding(.top, DSSpacing.s32)
                    .accessibilityIdentifier("floorPlan.delete.error")
            }

            Spacer()

            HStack(spacing: DSSpacing.s12) {
                Button("삭제") {
                    showsDeleteConfirmation = true
                }
                .buttonStyle(.dsSecondary)
                .frame(width: 132, height: DSSize.controlHeight)
                .accessibilityIdentifier("floorPlan.delete")

                Button("도면 수정", action: store.beginFloorPlanMaskEditing)
                    .buttonStyle(.dsPrimary)
                    .frame(maxWidth: .infinity, minHeight: DSSize.controlHeight)
                    .disabled(store.floorPlanDetailState != .loaded)
                    .accessibilityIdentifier("floorPlan.edit")
            }
        }
        .padding(.horizontal, DSSpacing.s20)
        .padding(.top, DSSpacing.s40)
        .padding(.bottom, 30)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.surfacePrimary)
    }

    private var deleteAlertTitle: String {
        guard let name = store.viewedFloorPlan?.name else { return "도면을 삭제하시겠습니까?" }
        return "‘\(name)’ 도면을 삭제하시겠습니까?"
    }

    private func formattedUpdatedAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy.MM.dd _ HH:mm"
        return formatter.string(from: date)
    }
}
