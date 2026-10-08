//
//  CQBFirebase.swift
//  CQB
//
//  Created by Dayoon Lee on 10/8/26.
//

import CQBCore
import Foundation
import FirebaseCore

public enum CQBFirebaseModule {
    /// 앱 시작 시 한 번 호출한다. GoogleService-Info.plist가 앱 번들에 없으면 건너뛴다.
    public static func configure() {
        guard FirebaseApp.app() == nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[CQBFirebase] GoogleService-Info.plist가 없어 Firebase 설정을 건너뜁니다.")
            return
        }
        FirebaseApp.configure()
    }
}
