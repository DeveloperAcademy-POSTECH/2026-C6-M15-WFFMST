import CQBFirebase
import os
import SwiftUI

@main
struct InstructorApp: App {
    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "InstructorApp")

    init() {
        CQBFirebaseModule.configure()
        Task {
            do {
                try await CQBFirebaseModule.signInAnonymously()
            } catch {
                Self.logger.error("익명 로그인 실패: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppContainer()
        }
    }
}
