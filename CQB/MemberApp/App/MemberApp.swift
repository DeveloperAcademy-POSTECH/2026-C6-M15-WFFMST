//
//  MemberApp.swift
//  CQB
//
//  Created by Dayoon Lee on 10/7/26.
//

import SwiftUI
import CQBCore

@main
struct MemberApp: App {
    @UIApplicationDelegateAdaptor(MemberAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppContainer()
        }
    }
}
