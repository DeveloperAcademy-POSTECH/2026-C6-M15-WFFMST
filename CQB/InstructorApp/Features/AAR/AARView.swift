import CQBCore
import SwiftUI

private enum AARLayout {
    static let outerHorizontalPadding: CGFloat = 24
    static let topPadding: CGFloat = 20
    static let bottomPadding: CGFloat = 32
    static let sectionSpacing: CGFloat = 16
    static let headerHeight: CGFloat = 52
    static let timelineHeight: CGFloat = 48
}

struct AARView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(AARStore.self) private var aarStore

    var body: some View {
        VStack(spacing: AARLayout.sectionSpacing) {
            header
                .frame(height: AARLayout.headerHeight)

            if store.trainingRecords.failedCount > 0 {
                Text("\(store.trainingRecords.failedCount)명의 기록 처리가 실패했습니다. 해당 기록의 재생 자료가 없을 수 있습니다.")
                    .font(.callout)
                    .foregroundStyle(InstructorColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("aar.recordingFailures")
            }

            AARContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            AARTimelineView()
                .frame(height: AARLayout.timelineHeight)
        }
        .padding(.top, AARLayout.topPadding)
        .padding(.horizontal, AARLayout.outerHorizontalPadding)
        .padding(.bottom, AARLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.currentSession?.id) { await loadTracks() }
        .onChange(of: store.selectedParticipantIDs, initial: true) { _, participantIDs in
            aarStore.showVideos(for: participantIDs)
        }
        // UT 영상을 남기려고 당분간 AAR을 떠나도 영상을 지우지 않는다(#66). Storage 자동 삭제도 꺼져 있다(docs/repositories.md).
        // 다시 지우려면 `aarStore.finish()`를 부른다.
        .onDisappear { aarStore.reset() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.currentSession?.name ?? "AAR")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(InstructorColor.textPrimary)

                Text(store.aarScreen == .floorPlan ? "도면·영상 복기" : "영상 비교")
                    .font(.caption)
                    .foregroundStyle(InstructorColor.textSecondary)
            }

            Spacer()

            Button(action: store.finishAAR) {
                Label("AAR 종료", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(InstructorColor.actionPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aar.finish")
        }
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
