//
//  AnonymousAuth.swift
//  CQB
//

import FirebaseAuth

/// Firebase 익명 로그인을 관리한다.
/// uid는 보안 규칙용 저장 전용 값이라 CQBFirebase 밖으로 내보내지 않는다 (데이터 계약 v1 2.1).
actor AnonymousAuth {
    static let shared = AnonymousAuth()

    private var signInTask: Task<String, Error>?

    /// 로그인돼 있으면 기존 uid를, 아니면 익명 로그인 후 새 uid를 돌려준다.
    /// 동시에 여러 번 불려도 로그인은 한 번만 일어난다.
    func uid() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }
        if let signInTask {
            return try await signInTask.value
        }

        let task = Task {
            try await Auth.auth().signInAnonymously().user.uid
        }
        signInTask = task
        defer { signInTask = nil }
        return try await task.value
    }
}
