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
        // AAR 화면을 떠나면(AAR 종료·홈) 다시 돌아오지 않으므로 이 세션의 영상을 지운다.
        .onDisappear { aarStore.finish() }
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
    ))
    store.startTraining()
    store.finishTraining()

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
    ))
    store.startTraining()
    store.finishTraining()
    store.toggleParticipantSelection("member-5")
    store.toggleParticipantSelection("member-6")
    store.changeAARMode(to: .video)

    return AARView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
