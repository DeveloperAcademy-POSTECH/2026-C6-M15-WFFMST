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
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            fatalError("[CQBFirebase] GoogleService-Info.plist가 앱 번들에 없습니다. MemberApp/ 또는 InstructorApp/ 폴더를 확인하세요.")
        }
        FirebaseApp.configure()
    }

    /// 앱 시작 시 미리 익명 로그인해 둔다. 이미 로그인돼 있으면 아무것도 하지 않는다.
    /// 실패해도 Firebase에 접근할 때 다시 시도하므로 호출하는 쪽은 앱을 멈추지 않는다.
    public static func signInAnonymously() async throws {
        let uid = try await AnonymousAuth.shared.uid()
        #if DEBUG
        print("[CQBFirebase] 익명 로그인 uid: \(uid)")
        #endif
    }
}
