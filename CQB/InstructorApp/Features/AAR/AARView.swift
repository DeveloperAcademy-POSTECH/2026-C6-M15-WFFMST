import SwiftUI

struct AARView: View {
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    AARContentView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    AARSettingsView()
                        .frame(width: min(300, max(220, geometry.size.width * 0.25)))
                }

                AARTimelineView()
            }
        }
        .padding()
    }
}

#Preview("AAR 동선") {
    let store = InstructorStore()
    store.openSessionCreation()
    store.createSession()
    store.startTraining()
    store.finishTraining()
    return AARView().environment(store)
}

#Preview("AAR 영상") {
    let store = InstructorStore()
    store.openSessionCreation()
    store.createSession()
    store.startTraining()
    store.finishTraining()
    store.toggleParticipantSelection("member-5")
    store.toggleParticipantSelection("member-6")
    store.changeAARMode(to: .video)
    return AARView().environment(store)
}
