//
//  FirestoreMemberRepository.swift
//  CQB
//

import CQBCore
import FirebaseFirestore

/// `sessions/{sessionID}/members/{memberID}`를 다룬다.
public struct FirestoreMemberRepository: MemberRepository {
    public init() {}

    public func join(_ member: Member, pin: String) async throws {
        let (db, uid) = try await FirebaseAccess.firestore()
        let data = try FirestoreEncoding.member(member, uid: uid, pin: pin)
        let pinDocument = try await FirestorePaths.pin(pin, in: db).getDocument()
        guard pinDocument.get("sessionID") as? String == member.sessionID.uuidString else {
            throw RepositoryError.notFound
        }
        let session = try await FirestorePaths.session(member.sessionID, in: db).getDocument()
        guard let raw = session.get("status") as? String,
              let status = SessionStatus(rawValue: raw) else {
            throw RepositoryError.notFound
        }
        guard Self.canJoin(status) else { throw RepositoryError.sessionClosed }
        try await document(of: member, in: db).setData(data)
    }

    /// 훈련이 시작되기 전(preparing, waiting)에만 입장할 수 있다.
    static func canJoin(_ status: SessionStatus) -> Bool {
        status == .preparing || status == .waiting
    }

    public func updateReadiness(of member: Member) async throws {
        let (db, _) = try await FirebaseAccess.firestore()
        try await document(of: member, in: db).updateData([
            "isReady": member.isReady,
            "lastActiveAt": FieldValue.serverTimestamp(),
        ])
    }

    public func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        FirestoreListening.stream { db, continuation in
            FirestorePaths.members(of: sessionID, in: db).addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                do {
                    let members = try (snapshot?.documents ?? []).map {
                        try FirestoreDecoding.decode(Member.self, from: $0)
                    }
                    continuation.yield(members)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func document(of member: Member, in db: Firestore) -> DocumentReference {
        FirestorePaths.members(of: member.sessionID, in: db).document(member.id.uuidString)
    }
}
