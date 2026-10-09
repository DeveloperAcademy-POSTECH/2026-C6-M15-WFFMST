import SwiftUI

struct AppContainer: View {
    @State private var store = InstructorStore()

    var body: some View {
        RootView()
            .environment(store)
            .environment(store.floorPlanDraft)
    }
}
