//
//  MemberApp.swift
//  CQB
//
//  Created by Dayoon Lee on 10/7/26.
//

import SwiftUI
import CQBCore
import CQBFirebase

@main
struct MemberApp: App {
    init() {
        CQBFirebaseModule.configure()
        Task {
            do {
                try await CQBFirebaseModule.signInAnonymously()
            } catch {
                print("[MemberApp] 익명 로그인 실패: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
