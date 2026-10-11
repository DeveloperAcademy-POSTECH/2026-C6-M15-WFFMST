//
//  FirestoreSessionRepository.swift
//  CQB
//

import CQBCore
import FirebaseFirestore

/// `pins/{pin}`과 `sessions/{sessionID}`를 다룬다.
public struct FirestoreSessionRepository: SessionRepository {
    public init() {}

    public func createSession(_ session: Session) async throws {
        let (db, uid) = try await FirebaseAccess.firestore()
        let pinRef = FirestorePaths.pin(session.pin, in: db)
        let sessionRef = FirestorePaths.session(session.id, in: db)
        let pinData = FirestoreEncoding.pin(sessionID: session.id)
        let sessionData = try FirestoreEncoding.session(session, instructorUid: uid)

        // PIN 확인과 생성을 한 번에 해서, 두 교관이 같은 PIN을 동시에 만들지 못하게 한다.
        let created = try await db.runTransaction { transaction, errorPointer in
            do {
                if try transaction.getDocument(pinRef).exists { return false }
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            transaction.setData(pinData, forDocument: pinRef)
            transaction.setData(sessionData, forDocument: sessionRef)
            return true
        }
        guard created as? Bool == true else { throw RepositoryError.pinTaken }
    }

    public func session(forPin pin: String) async throws -> Session {
        let (db, _) = try await FirebaseAccess.firestore()
        guard let pinData = try await FirestorePaths.pin(pin, in: db).getDocument().data() else {
            throw RepositoryError.notFound
        }
        let sessionID = try FirestoreDecoding.sessionID(fromPin: pinData)
        let snapshot = try await FirestorePaths.session(sessionID, in: db).getDocument()
        guard snapshot.exists else { throw RepositoryError.notFound }
        return try FirestoreDecoding.decode(Session.self, from: snapshot)
    }

    public func updateStatus(of session: Session, to status: SessionStatus) async throws {
        let (db, _) = try await FirebaseAccess.firestore()
        var fields: [String: Any] = ["status": status.rawValue]
        if status == .running {
            fields["startedAt"] = FieldValue.serverTimestamp()
        }
        let batch = db.batch()
        batch.updateData(fields, forDocument: FirestorePaths.session(session.id, in: db))
        if status == .ended {
            batch.deleteDocument(FirestorePaths.pin(session.pin, in: db))
        }
        try await batch.commit()
    }

    public func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        FirestoreListening.stream { db, continuation in
            FirestorePaths.session(id, in: db).addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let snapshot, snapshot.exists else {
                    continuation.finish(throwing: RepositoryError.notFound)
                    return
                }
                do {
                    continuation.yield(try FirestoreDecoding.decode(Session.self, from: snapshot))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
