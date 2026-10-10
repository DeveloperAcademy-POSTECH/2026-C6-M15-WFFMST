import SwiftUI
import UIKit

struct AppContainer: View {
    @State private var store = MemberStore()

    var body: some View {
        RootView()
            .environment(store)
            .background(MemberOrientation(
                usesLandscape: store.phase == .waiting || store.phase == .recording || store.phase == .saving || store.phase == .correcting
            ))
            .onAppear { updateIdleTimer(for: store.phase) }
            .onChange(of: store.phase) { _, phase in updateIdleTimer(for: phase) }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func updateIdleTimer(for phase: MemberPhase) {
        UIApplication.shared.isIdleTimerDisabled = phase == .recording || phase == .saving || phase == .correcting
    }
}

#Preview {
    AppContainer()
}
