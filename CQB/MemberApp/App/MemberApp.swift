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
    @UIApplicationDelegateAdaptor(MemberAppDelegate.self) private var appDelegate
    
    init() {
        CQBFirebaseModule.configure()
    }

    var body: some Scene {
        WindowGroup {
            AppContainer()
        }
    }
}
