import CQBCore
import CQBDesignSystem
import SwiftUI

enum AARLayout {
    static let outerHorizontalPadding = DSSpacing.s8
    static let contentGap = DSSpacing.s8
    static let videoGridGap = DSSpacing.s4
    static let headerHorizontalPadding = DSSpacing.s40
    static let headerHeight: CGFloat = 81
    static let contentHeaderHeight: CGFloat = 48
    static let timelineHeight: CGFloat = 147
    static let timelineHorizontalPadding = DSSpacing.s40
}

struct AARView: View {
    private static let videoLoadingGuideMessage =
        "영상을 불러오는 데 시간이 소요됩니다. 대원을 선택한 후 잠시만 기다려 주세요."

    @Environment(InstructorStore.self) private var store
    @Environment(AARStore.self) private var aarStore
    @State private var showsFinishConfirmation = false
    @State private var showsVideoLoadingGuide = true

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: AARLayout.headerHeight)

            AARContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        recordingFailureNotice
                            .frame(maxWidth: .infinity, alignment: .leading)

                        videoLoadingGuide
                    }
                }

            AARTimelineView()
                .frame(height: AARLayout.timelineHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.aarCanvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert("AAR을 종료하시겠습니까?", isPresented: $showsFinishConfirmation) {
            Button("확인", action: store.finishAAR)
            Button("취소", role: .cancel) {}
        } message: {
            Text("이전 훈련 기록에서 현재 AAR을 다시 사용가능합니다.")
        }
        .task(id: store.currentSession?.id) { await loadTracks() }
        .onChange(of: store.selectedParticipantIDs, initial: true) { _, participantIDs in
            aarStore.showVideos(for: participantIDs)
        }
        // UT 영상을 남기려고 당분간 AAR을 떠나도 영상을 지우지 않는다(#66). Storage 자동 삭제도 꺼져 있다(docs/repositories.md).
        // 다시 지우려면 `aarStore.finish()`를 부른다.
        .onDisappear { aarStore.reset() }
    }

    @ViewBuilder
    private var videoLoadingGuide: some View {
        if showsVideoLoadingGuide {
            DSGuideToast(
                Self.videoLoadingGuideMessage,
                onDismiss: { showsVideoLoadingGuide = false },
                dismissAccessibilityIdentifier: "aar.videoLoadingGuide.dismiss"
            )
            .frame(maxWidth: 690)
            .padding(.top, DSSpacing.s12)
            .accessibilityIdentifier("aar.videoLoadingGuide")
        }
    }

    private var header: some View {
        HStack(spacing: DSSpacing.s16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.currentSession?.name ?? "AAR")
                    .dsTextStyle(DSTypography.headingSemiBold24)
                    .foregroundStyle(InstructorColor.aarContentPrimary)

                Text(sessionDateText)
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(InstructorColor.aarContentPrimary)
            }

            Spacer()

            Button {
                showsFinishConfirmation = true
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                        .font(.system(size: 29, weight: .regular))

                    Text("AAR 종료")
                        .font(.caption)
                }
                    .foregroundStyle(InstructorColor.aarActionPrimary)
                    .frame(width: 56, height: 60)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aar.finish")
        }
        .padding(.horizontal, AARLayout.headerHorizontalPadding)
        .background(InstructorColor.aarCanvas)
    }

    @ViewBuilder
    private var recordingFailureNotice: some View {
        if store.trainingRecords.failedCount > 0 {
            Text("\(store.trainingRecords.failedCount)명의 기록 처리가 실패했습니다. 해당 기록의 재생 자료가 없을 수 있습니다.")
                .dsTextStyle(DSTypography.captionRegular14)
                .foregroundStyle(InstructorColor.aarContentSecondary)
                .padding(DSSpacing.s12)
                .background(InstructorColor.aarSurfaceRaised.opacity(0.94))
                .clipShape(.rect(cornerRadius: DSRadius.small))
                .padding(DSSpacing.s12)
                .accessibilityIdentifier("aar.recordingFailures")
        }
    }

    private var sessionDateText: String {
        guard let date = store.currentSession?.startedAt else { return "" }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else { return "" }
        return String(format: "%04d.%02d.%02d", year, month, day)
    }

    private func loadTracks() async {
        guard let session = store.currentSession else { return }
        await aarStore.load(
            session: session,
            participantIDs: store.aarParticipants.map(\.id),
            localFloorPlan: store.selectedFloorPlan?.registeredPlan
        )
    }
}

#Preview("AAR 동선") {
    let store = InstructorPreviewFixture.store(floorPlan: InstructorFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    ), phase: .aar)

    return AARView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#Preview("AAR 영상 로딩 안내 토스트") {
    let store = InstructorPreviewFixture.store(floorPlan: InstructorFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    ), phase: .aar)

    return AARView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#Preview("AAR 영상") {
    let store = InstructorPreviewFixture.store(floorPlan: InstructorFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    ), phase: .aar)
    store.toggleParticipantSelection("member-5")
    store.toggleParticipantSelection("member-6")
    store.openAARVideoScreen()

    return AARView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
