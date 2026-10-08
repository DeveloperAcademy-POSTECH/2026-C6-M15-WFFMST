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
    /// 앱 시작 시 한 번 호출한다. GoogleService-Info.plist가 앱 번들에 없으면 즉시 중단한다.
    public static func configure() {
        guard FirebaseApp.app() == nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            fatalError("[CQBFirebase] GoogleService-Info.plist가 앱 번들에 없습니다. MemberApp/ 또는 InstructorApp/ 폴더를 확인하세요.")
        }
        FirebaseApp.configure()
    }
}
