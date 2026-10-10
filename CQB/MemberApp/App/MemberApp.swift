//
//  MemberApp.swift
//  CQB
//
//  Created by Dayoon Lee on 10/7/26.
//

import SwiftUI
import CQBCore
import CQBFirebase
import os

@main
struct MemberApp: App {
    @UIApplicationDelegateAdaptor(MemberAppDelegate.self) private var appDelegate
    
    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "MemberApp")

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
