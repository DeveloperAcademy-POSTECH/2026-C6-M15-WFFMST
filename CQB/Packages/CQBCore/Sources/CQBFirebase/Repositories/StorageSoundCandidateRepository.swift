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
        try document.validate()
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
    /// 받은 문서가 요청한 기록의 것이고 계약을 지키는지 확인한다.
    /// 모르는 버전은 `SoundCandidateValidationError.unsupportedSchema`, 손상된 문서는 그 밖의 검증 오류로 알린다.
    static func decode(_ data: Data, for identity: TrackIdentity) throws -> SoundCandidateDocument {
        let document = try JSONDecoder().decode(SoundCandidateDocument.self, from: data)
        guard document.identity == identity else { throw RepositoryError.integrityMismatch }
        try document.validate()
        return document
    }
}
