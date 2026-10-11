//
//  FirestoreRecordingRepository.swift
//  CQB
//

import CQBCore
import FirebaseFirestore

/// `sessions/{sessionID}/recordings/{recordingID}`를 다룬다.
public struct FirestoreRecordingRepository: RecordingRepository {
    public init() {}

    public func startRecording(_ recording: Recording) async throws {
        try await write(recording, stampStartedAt: true)
    }

    public func updateRecording(_ recording: Recording) async throws {
        try await write(recording, stampStartedAt: false)
    }

    public func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        FirestoreListening.stream { db, continuation in
            FirestorePaths.recordings(of: sessionID, in: db).addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                do {
                    let recordings = try (snapshot?.documents ?? []).map {
                        try FirestoreDecoding.decode(Recording.self, from: $0)
                    }
                    continuation.yield(recordings)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// `merge: true`라서 모델에서 nil인 값(예: 아직 모르는 `startedAt`)이 서버에 있던 값을 지우지 않는다.
    private func write(_ recording: Recording, stampStartedAt: Bool) async throws {
        let (db, _) = try await FirebaseAccess.firestore()
        let data = try FirestoreEncoding.recording(recording, stampStartedAt: stampStartedAt)
        try await FirestorePaths.recordings(of: recording.identity.sessionID, in: db)
            .document(recording.id.uuidString)
            .setData(data, merge: true)
    }
}
