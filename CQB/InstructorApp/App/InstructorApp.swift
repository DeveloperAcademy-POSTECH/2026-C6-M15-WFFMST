import CQBFirebase
import SwiftUI

@main
struct InstructorApp: App {
    init() {
        CQBFirebaseModule.configure()
        Task {
            do {
                try await CQBFirebaseModule.signInAnonymously()
            } catch {
                print("[InstructorApp] 익명 로그인 실패: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppContainer()
        }
    }
}
