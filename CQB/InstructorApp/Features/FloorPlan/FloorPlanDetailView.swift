import CQBDesignSystem
import SwiftUI

struct FloorPlanDetailView: View {
    @Environment(InstructorStore.self) private var store
    @State private var layers = FloorPlanLayerDisplay(planOpacity: 0.65, maskOpacity: 0.55)
    @State private var showsDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                preview
            }
            .containerRelativeFrame(.horizontal, count: 10, span: 7, spacing: 0)
            .frame(maxHeight: .infinity)
            .background(InstructorColor.canvas)

            detailPanel
                .containerRelativeFrame(.horizontal, count: 10, span: 3, spacing: 0)
        }
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert("도면을 목록에서 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive, action: store.deleteViewedFloorPlan)
        } message: {
            Text("도면은 새 세션에서 선택할 수 없게 됩니다. 기존 세션이 참조하는 파일은 유지됩니다.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            InstructorBackButton(action: store.goBack)
                .disabled(!store.canGoBack)

            Text(store.viewedFloorPlan?.fileName ?? "도면 상세")
                .font(DSTypography.h2)
                .foregroundStyle(InstructorColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("도면 미리보기")
                .font(DSTypography.h3)
                .foregroundStyle(InstructorColor.textPrimary)

            Group {
                switch store.floorPlanDetailState {
                case .idle, .loading:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("도면과 마스크를 불러오는 중입니다.")
                    }
                    .foregroundStyle(InstructorColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("floorPlan.detail.loading")
                case .failed(let message):
                    VStack(spacing: 20) {
                        ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
                        ActionButton("다시 불러오기", action: store.retryFloorPlanDetailLoad)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("floorPlan.detail.error")
                case .loaded:
                    loadedCanvas
                }
            }
            .clipShape(.rect(cornerRadius: 4))

            if store.floorPlanDetailState == .loaded {
                FloorPlanLayerControls(display: $layers)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var loadedCanvas: some View {
        if let image = store.floorPlanDetailImage {
            LocalFloorPlanCanvas(
                image: image,
                mask: store.floorPlanDetailMaskImage,
                tool: .move,
                normalizedDiameter: 0.006,
                outline: [],
                layers: layers,
                onStroke: { _ in },
                onPoint: { _ in }
            )
            .accessibilityIdentifier("floorPlan.detail.canvas")
        } else {
            ContentUnavailableView("도면 미리보기를 표시할 수 없습니다.", systemImage: "map")
        }
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let plan = store.viewedFloorPlan {
                Text(plan.name)
                    .font(DSTypography.h1)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .accessibilityIdentifier("floorPlan.detail.name")

                Text("최종 수정 시간")
                    .font(DSTypography.h3)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .padding(.top, 72)

                Text(plan.updatedAt.formatted(
                    .dateTime
                        .year().month(.twoDigits).day(.twoDigits)
                        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                        .locale(Locale(identifier: "ko_KR"))
                ))
                .font(DSTypography.body)
                .foregroundStyle(InstructorColor.textSecondary)
                .padding(.top, 12)
                .accessibilityIdentifier("floorPlan.detail.updatedAt")
            }

            if let error = store.floorPlanDeletionError {
                Text(error)
                    .font(DSTypography.bodySmall)
                    .foregroundStyle(InstructorColor.validationError)
                    .padding(.top, 32)
                    .accessibilityIdentifier("floorPlan.delete.error")
            }

            Spacer()

            HStack(spacing: 12) {
                ActionButton("도면 삭제", role: .destructive, tone: .secondary, fillsWidth: true) {
                    showsDeleteConfirmation = true
                }
                .accessibilityIdentifier("floorPlan.delete")

                ActionButton("수정하기", fillsWidth: true, action: store.beginFloorPlanMaskEditing)
                    .disabled(store.floorPlanDetailState != .loaded)
                    .accessibilityIdentifier("floorPlan.edit")
            }
            .frame(height: 52)
        }
        .padding(.horizontal, 24)
        .padding(.top, 48)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.surfaceBase)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(InstructorColor.borderDefault)
                .frame(width: 1)
        }
    }
}
