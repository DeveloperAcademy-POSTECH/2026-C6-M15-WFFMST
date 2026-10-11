//
//  FirestoreDecoding.swift
//  CQB
//

import CQBCore
import FirebaseFirestore

enum FirestoreDecodingError: Error, Equatable {
    /// 문서가 없다. 예: 없는 PIN으로 입장
    case documentNotFound
    /// `pins/{pin}` 문서의 `sessionID`가 없거나 UUID가 아니다.
    case invalidPin
}

/// Firestore 문서를 Core 모델로 바꾼다 (`FirestoreEncoding`의 반대).
/// 저장 전용 필드(`instructorUid`, `uid`, `pin`)는 모델에 없으므로 읽을 때 버려진다.
enum FirestoreDecoding {
    /// 저장 직후 아직 서버 시각이 확정되지 않은 필드는 추정값으로 채운다.
    /// 그대로 두면 `lastActiveAt`처럼 nil이 될 수 없는 필드에서 읽기가 실패한다.
    static func decode<Model: Decodable>(_ type: Model.Type, from snapshot: DocumentSnapshot) throws -> Model {
        guard let data = snapshot.data(with: .estimate) else {
            throw FirestoreDecodingError.documentNotFound
        }
        return try decode(type, from: data)
    }

    static func decode<Model: Decodable>(_ type: Model.Type, from data: [String: Any]) throws -> Model {
        try Firestore.Decoder().decode(type, from: data)
    }

    /// `pins/{pin}` 문서에서 세션 ID를 꺼낸다.
    static func sessionID(fromPin data: [String: Any]) throws -> UUID {
        guard let value = data["sessionID"] as? String, let sessionID = UUID(uuidString: value) else {
            throw FirestoreDecodingError.invalidPin
        }
        return sessionID
    }
}
