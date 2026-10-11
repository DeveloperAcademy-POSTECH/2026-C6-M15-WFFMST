//
//  CQBFirebase.swift
//  CQB
//
//  Created by Dayoon Lee on 10/8/26.
//

import CQBCore
import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import os

public enum CQBFirebaseModule {
    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "CQBFirebase")

    /// 앱 시작 시 한 번 호출한다. GoogleService-Info.plist가 앱 번들에 없으면 즉시 중단한다.
    public static func configure() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            fatalError("[CQBFirebase] GoogleService-Info.plist가 앱 번들에 없습니다. MemberApp/ 또는 InstructorApp/ 폴더를 확인하세요.")
        }
        FirebaseApp.configure()
        useEmulatorIfRequested()
    }

    /// 디버그 빌드에서 Xcode 스킴 환경 변수 `FIREBASE_EMULATOR_HOST`가 있으면 로컬 에뮬레이터에 연결한다.
    /// 시뮬레이터는 `localhost`, 실제 기기는 같은 와이파이에 있는 맥의 IP를 넣는다. 릴리스 빌드는 항상 운영 Firebase에 연결한다.
    private static func useEmulatorIfRequested() {
        #if DEBUG
        let host = ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"].flatMap { $0.isEmpty ? nil : $0 }
        if let host {
            Auth.auth().useEmulator(withHost: host, port: 9099)
            Firestore.firestore().useEmulator(withHost: host, port: 8080)
            Storage.storage().useEmulator(withHost: host, port: 9199)
            logger.notice("Firebase 에뮬레이터 사용: \(host, privacy: .public)")
        }
        signOutIfTargetChanged(to: host ?? "production")
        #endif
    }

    #if DEBUG
    private static let lastTargetKey = "com.wffmst.cqb.firebaseTarget"

    /// 운영과 에뮬레이터를 오가면 기기에 남은 다른 쪽 로그인으로 요청이 실패한다.
    /// 로그인 정보는 키체인에 있어 앱을 지워도 남으므로, 연결 대상이 바뀌면 로그아웃해 새로 익명 로그인하게 한다.
    private static func signOutIfTargetChanged(to target: String) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: lastTargetKey) != target else { return }
        do {
            try Auth.auth().signOut()
            defaults.set(target, forKey: lastTargetKey)
            logger.notice("Firebase 연결 대상이 바뀌어 로그아웃: \(target, privacy: .public)")
        } catch {
            logger.error("Firebase 로그아웃 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    /// 앱 시작 시 미리 익명 로그인해 둔다. 이미 로그인돼 있으면 아무것도 하지 않는다.
    /// 실패해도 Firebase에 접근할 때 다시 시도하므로 호출하는 쪽은 앱을 멈추지 않는다.
    public static func signInAnonymously() async throws {
        let uid = try await AnonymousAuth.shared.uid()
        logger.debug("익명 로그인 완료 uid: \(uid, privacy: .private)")
    }
}
