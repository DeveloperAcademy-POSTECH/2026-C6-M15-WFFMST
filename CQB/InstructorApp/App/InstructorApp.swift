import CQBFirebase
import SwiftUI

@main
struct InstructorApp: App {
    init() {
        CQBFirebaseModule.configure()
    }

    var body: some Scene {
        WindowGroup {
            AppContainer()
        }
    }
}
