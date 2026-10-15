//
//  AnonymousAuth.swift
//  CQB
//

import FirebaseAuth
import Foundation

/// Firebase 익명 로그인을 관리한다.
/// uid는 보안 규칙용 저장 전용 값이라 CQBFirebase 밖으로 내보내지 않는다 (데이터 계약 v1 2.1).
actor AnonymousAuth {
    static let shared = AnonymousAuth()

    private var signInTask: Task<String, Error>?
    #if DEBUG
    private var validatedEmulatorUID: String?
    #endif

    /// 로그인돼 있으면 기존 uid를, 아니면 익명 로그인 후 새 uid를 돌려준다.
    /// 동시에 여러 번 불려도 로그인은 한 번만 일어난다.
    func uid() async throws -> String {
        if let user = Auth.auth().currentUser {
            #if DEBUG
            if isUsingEmulator, validatedEmulatorUID != user.uid {
                do {
                    _ = try await user.getIDToken(forcingRefresh: true)
                    validatedEmulatorUID = user.uid
                } catch {
                    guard !isNetworkError(error) else { throw error }

                    // Auth Emulator를 재시작하면 Simulator 키체인에 남은 refresh token은
                    // 더 이상 유효하지 않다. 로컬 개발 환경에서만 폐기된 인증을 지우고
                    // 아래 익명 로그인 경로로 복구한다.
                    try Auth.auth().signOut()
                    validatedEmulatorUID = nil
                }
            }

            if let currentUID = Auth.auth().currentUser?.uid {
                return currentUID
            }
            #else
            return user.uid
            #endif
        }
        if let signInTask {
            return try await signInTask.value
        }

        let task = Task {
            let uid = try await Auth.auth().signInAnonymously().user.uid
            #if DEBUG
            if isUsingEmulator {
                validatedEmulatorUID = uid
            }
            #endif
            return uid
        }
        signInTask = task
        defer { signInTask = nil }
        return try await task.value
    }

    #if DEBUG
    private var isUsingEmulator: Bool {
        ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"]?.isEmpty == false
    }

    private func isNetworkError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == AuthErrorDomain && error.code == AuthErrorCode.networkError.rawValue
    }
    #endif
}
