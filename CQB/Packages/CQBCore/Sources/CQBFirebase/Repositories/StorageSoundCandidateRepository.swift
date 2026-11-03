//
//  StorageSoundCandidateRepository.swift
//  CQB
//

import CQBCore
import Foundation

/// `sessions/{sessionID}/recordings/{recordingID}/sound-candidates.json`을 다룬다.
public struct StorageSoundCandidateRepository: SoundCandidateRepository {
    public init() {}

    public func upload(_ document: SoundCandidateDocument) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try await StorageTransfer.upload(
            try encoder.encode(document),
            to: StoragePaths.soundCandidates(document.identity),
            contentType: "application/json"
        )
    }

    public func download(_ identity: TrackIdentity) async throws -> SoundCandidateDocument {
        let data = try await StorageTransfer.download(StoragePaths.soundCandidates(identity))
        return try SoundCandidateFileValidation.decode(data, for: identity)
    }
}

enum SoundCandidateFileValidation {
    /// 받은 문서가 요청한 기록의 것인지 확인한다.
    static func decode(_ data: Data, for identity: TrackIdentity) throws -> SoundCandidateDocument {
        let document = try JSONDecoder().decode(SoundCandidateDocument.self, from: data)
        guard document.identity == identity else { throw RepositoryError.integrityMismatch }
        return document
    }
}
