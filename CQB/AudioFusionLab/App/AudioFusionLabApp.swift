import SwiftUI

@main
struct AudioFusionLabApp: App {
    @State private var store = ExperimentStore()

    var body: some Scene {
        WindowGroup {
            ExperimentRootView()
                .environment(store)
        }
    }
}
