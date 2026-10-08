//
//  InstructorAppApp.swift
//  InstructorApp
//
//  Created by Dayoon Lee on 10/7/26.
//

import SwiftUI
import CQBCore
import CQBFirebase

@main
struct InstructorAppApp: App {
    init() {
        CQBFirebaseModule.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
