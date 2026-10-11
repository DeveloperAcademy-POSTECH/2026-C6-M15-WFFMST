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
    }
}

#Preview("AAR 동선") {
    let store = InstructorStore(floorPlans: [
        DemoFloorPlan(
            id: "preview-plan",
            name: "훈련장 A 도면",
            fileName: "훈련장 A 도면.png",
            referenceDistance: 15
        )
    ])
    store.openSessionCreation()
    store.createSession()
    store.startTraining()
    store.finishTraining()

    return AARView()
        .environment(store)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#Preview("AAR 영상") {
    let store = InstructorStore(floorPlans: [
        DemoFloorPlan(
            id: "preview-plan",
            name: "훈련장 A 도면",
            fileName: "훈련장 A 도면.png",
            referenceDistance: 15
        )
    ])
    store.openSessionCreation()
    store.createSession()
    store.startTraining()
    store.finishTraining()
    store.toggleParticipantSelection("member-5")
    store.toggleParticipantSelection("member-6")
    store.changeAARMode(to: .video)

    return AARView()
        .environment(store)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
