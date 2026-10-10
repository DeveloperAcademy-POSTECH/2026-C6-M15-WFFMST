//
//  FirebaseAccess.swift
//  CQB
//

import FirebaseFirestore
import FirebaseStorage

/// Firestore·Storage를 꺼내는 유일한 입구.
/// 익명 로그인이 끝난 뒤에만 돌려주므로, 앱 시작 직후 로그인 전에 요청이 나가 보안 규칙에 거부되는 일을 막는다.
/// CQBFirebase 안에서는 `Firestore.firestore()`·`Storage.storage()`를 직접 부르지 않고 이 함수를 쓴다.
enum FirebaseAccess {
    /// 로그인을 보장한 뒤 Firestore와 uid를 돌려준다. uid는 저장 전용 필드(`instructorUid`, `uid`)에 쓴다.
    static func firestore() async throws -> (db: Firestore, uid: String) {
        let uid = try await AnonymousAuth.shared.uid()
        return (Firestore.firestore(), uid)
    }

    /// 로그인을 보장한 뒤 Storage와 uid를 돌려준다.
    static func storage() async throws -> (storage: Storage, uid: String) {
        let uid = try await AnonymousAuth.shared.uid()
        return (Storage.storage(), uid)
    }
}
