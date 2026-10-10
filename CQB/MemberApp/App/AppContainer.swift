import SwiftUI

struct AppContainer: View {
    @State private var store = MemberStore()

    var body: some View {
        RootView()
            .environment(store)
            .background(MemberOrientation(usesLandscape: store.phase == .waiting || store.phase == .recording))
    }
}

#Preview {
    AppContainer()
}
