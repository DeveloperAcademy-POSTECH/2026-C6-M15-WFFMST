import SwiftUI
import UIKit
import CQBFirebase

struct AppContainer: View {
    @State private var store = MemberStore(
        sessionRepository: FirestoreSessionRepository(),
        memberRepository: FirestoreMemberRepository(),
        floorPlanFileRepository: StorageFloorPlanFileRepository(),
        recordingRepository: FirestoreRecordingRepository(),
        videoChunkRepository: StorageVideoChunkRepository(),
        trackResultRepository: StorageTrackResultRepository()
    )
    @State private var demoMode = MemberDemoMode()

    var body: some View {
        Group {
            if demoMode.isActive {
                MemberDemoContainer()
                    .id(demoMode.runID)
            } else {
                MemberExperienceContainer(store: store)
            }
        }
        .environment(demoMode)
    }
}

@MainActor
private struct MemberDemoContainer: View {
    @State private var environment = MemberDemoScenario.makeEnvironment()

    var body: some View {
        MemberExperienceContainer(store: environment.store, demoControl: environment.control)
            .task { environment.enter() }
            .onDisappear { environment.store.shutdown() }
    }
}

@MainActor
private struct MemberExperienceContainer: View {
    let store: MemberStore
    var demoControl: MemberDemoSessionControl?

    var body: some View {
        RootView(demoControl: demoControl)
            .environment(store)
            .background(MemberOrientation(
                usesLandscape: store.phase == .waiting
                    || store.phase == .recording
                    || store.phase == .saving
                    || store.phase == .correcting
            ))
            .onAppear { updateIdleTimer(for: store.phase) }
            .onChange(of: store.phase) { _, phase in updateIdleTimer(for: phase) }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func updateIdleTimer(for phase: MemberPhase) {
        UIApplication.shared.isIdleTimerDisabled = phase == .recording
            || phase == .saving
            || phase == .correcting
    }
}

#Preview {
    AppContainer()
}
