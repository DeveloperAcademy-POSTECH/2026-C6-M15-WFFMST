//
//  FirestoreEncoding.swift
//  CQB
//

import CQBCore
import FirebaseFirestore

/// Core 모델을 Firestore에 저장할 데이터로 바꾼다 (`docs/cqb-core-models.md` Firestore 계약).
/// `Date`는 `Timestamp`, `UUID`는 문자열이 되고, 저장 전용 필드와 서버 시각은 여기서만 붙인다.
enum FirestoreEncoding {
    /// 모델을 인코딩한 뒤 저장 전용 필드를 덧붙이고, 지정한 필드를 서버 시각으로 바꾼다.
    static func encode<Model: Encodable>(
        _ model: Model,
        adding storageOnly: [String: Any] = [:],
        serverTimestamps: Set<String> = []
    ) throws -> [String: Any] {
        var data = try Firestore.Encoder().encode(model)
        data.merge(storageOnly) { _, storageOnly in storageOnly }
        for field in serverTimestamps {
            data[field] = FieldValue.serverTimestamp()
        }
        return data
    }

    /// `pins/{pin}`
    static func pin(sessionID: UUID) -> [String: Any] {
        ["sessionID": sessionID.uuidString]
    }

    /// `sessions/{sessionID}`. 훈련을 시작할 때만 `stampStartedAt`을 켠다.
    static func session(_ session: Session, instructorUid: String, stampStartedAt: Bool = false) throws -> [String: Any] {
        try encode(
            session,
            adding: ["instructorUid": instructorUid],
            serverTimestamps: stampStartedAt ? ["startedAt"] : []
        )
    }

    /// `sessions/{sessionID}/members/{memberID}`. `lastActiveAt`은 저장할 때마다 서버 시각이 된다.
    static func member(_ member: Member, uid: String, pin: String) throws -> [String: Any] {
        try encode(
            member,
            adding: ["uid": uid, "pin": pin],
            serverTimestamps: ["lastActiveAt"]
        )
    }

    /// `sessions/{sessionID}/recordings/{recordingID}`. 기록을 시작할 때만 `stampStartedAt`을 켠다.
    /// `lastActiveAt`은 저장할 때마다 서버 시각이 된다.
    static func recording(_ recording: Recording, stampStartedAt: Bool = false) throws -> [String: Any] {
        try encode(
            recording,
            serverTimestamps: stampStartedAt ? ["startedAt", "lastActiveAt"] : ["lastActiveAt"]
        )
    }
}
