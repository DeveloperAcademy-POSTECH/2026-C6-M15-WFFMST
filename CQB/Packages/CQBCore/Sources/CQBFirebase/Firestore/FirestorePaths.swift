//
//  FirestorePaths.swift
//  CQB
//

import FirebaseFirestore

/// Firestore 문서 경로 (`docs/cqb-core-models.md` 경로와 모델). 경로 문자열은 여기서만 만든다.
enum FirestorePaths {
    static func pin(_ pin: String, in db: Firestore) -> DocumentReference {
        db.collection("pins").document(pin)
    }

    static func session(_ sessionID: UUID, in db: Firestore) -> DocumentReference {
        db.collection("sessions").document(sessionID.uuidString)
    }

    static func members(of sessionID: UUID, in db: Firestore) -> CollectionReference {
        session(sessionID, in: db).collection("members")
    }

    static func recordings(of sessionID: UUID, in db: Firestore) -> CollectionReference {
        session(sessionID, in: db).collection("recordings")
    }
}
