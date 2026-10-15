//
//  StorageTrackResultRepository.swift
//  CQB
//

import CQBCore
import Foundation

/// `sessions/{sessionID}/recordings/{recordingID}/result.json`을 다룬다.
public struct StorageTrackResultRepository: TrackResultRepository {
    public init() {}

    public func upload(_ result: TrackResultDocument) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try await StorageTransfer.upload(
            try encoder.encode(result),
            to: StoragePaths.trackResult(result.identity),
            contentType: "application/json"
        )
    }

    public func download(_ identity: TrackIdentity) async throws -> TrackResultDocument {
        let data = try await StorageTransfer.download(StoragePaths.trackResult(identity))
        return try JSONDecoder().decode(TrackResultDocument.self, from: data)
    }
}
