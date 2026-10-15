import CQBCore
import SwiftUI

private enum AARLayout {
    static let outerHorizontalPadding: CGFloat = 24
    static let topPadding: CGFloat = 24
    static let bottomPadding: CGFloat = 32
    static let contentToSettingsSpacing: CGFloat = 12
    static let contentToTimelineSpacing: CGFloat = 24
    static let timelineHeight: CGFloat = 48
}

struct AARView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(AARStore.self) private var aarStore

    var body: some View {
        GeometryReader { geometry in
            let settingsWidth = min(298, max(240, geometry.size.width * 0.22))

            DropdownHost {
                VStack(spacing: AARLayout.contentToTimelineSpacing) {
                    if store.trainingRecords.failedCount > 0 {
                        Text("\(store.trainingRecords.failedCount)명의 기록 처리가 실패했습니다. 해당 기록의 재생 자료가 없을 수 있습니다.")
                            .font(.callout)
                            .foregroundStyle(InstructorColor.textSecondary)
                            .accessibilityIdentifier("aar.recordingFailures")
                    }
                    HStack(alignment: .top, spacing: AARLayout.contentToSettingsSpacing) {
                        AARContentView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        AARSettingsView()
                            .frame(width: settingsWidth)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    AARTimelineView()
                        .frame(height: AARLayout.timelineHeight)
                }
                .padding(.top, AARLayout.topPadding)
                .padding(.horizontal, AARLayout.outerHorizontalPadding)
                .padding(.bottom, AARLayout.bottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.currentSession?.id) { await loadTracks() }
        // UT 영상을 남기려고 당분간 AAR을 떠나도 영상을 지우지 않는다(#66). Storage 자동 삭제도 꺼져 있다(docs/repositories.md).
        // 다시 지우려면 `aarStore.finish()`를 부른다.
        .onDisappear { aarStore.reset() }
    }

    private func loadTracks() async {
        guard let session = store.currentSession else { return }
        await aarStore.load(
            session: session,
            participantIDs: store.participants.map(\.id),
            localFloorPlan: store.selectedFloorPlan?.registeredPlan
        )
    }
}

#Preview("AAR 동선") {
    let store = InstructorPreviewFixture.store(floorPlan: DemoFloorPlan(
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
    let store = InstructorPreviewFixture.store(floorPlan: DemoFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    ), phase: .aar)
    store.toggleParticipantSelection("member-5")
    store.toggleParticipantSelection("member-6")
    store.changeAARMode(to: .video)

    return AARView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
