import CQBCore
import Foundation

/// `worldMaps/{worldMapID}/` 아래 불변 스캔 파일 2개를 다룬다.
public struct StorageWorldMapFileRepository: WorldMapFileRepository {
    public init() {}

    public func upload(_ files: WorldMapFiles, for reference: WorldMapReference) async throws {
        _ = try WorldMapFileValidation.validate(files, against: reference)
        try await StorageTransfer.uploadIfMissingOrMatching(
            files.worldMapArchive,
            to: StoragePaths.worldMapArchive(reference),
            contentType: "application/octet-stream",
            maxBytes: StorageTransfer.maxWorldMapBytes
        )
        try await StorageTransfer.uploadIfMissingOrMatching(
            files.setupJSON,
            to: StoragePaths.worldMapSetup(reference),
            contentType: "application/json",
            maxBytes: StorageTransfer.maxWorldMapSetupBytes
        )
    }

    public func download(_ reference: WorldMapReference) async throws -> WorldMapFiles {
        let setup = try await StorageTransfer.download(
            StoragePaths.worldMapSetup(reference),
            maxBytes: StorageTransfer.maxWorldMapSetupBytes
        )
        guard StorageTransfer.sha256(setup) == reference.setupSHA256.lowercased(),
              let decoded = try? JSONDecoder().decode(WorldMapSetup.self, from: setup),
              decoded.matches(reference) else {
            throw RepositoryError.integrityMismatch
        }
        let archive = try await StorageTransfer.download(
            StoragePaths.worldMapArchive(reference),
            maxBytes: StorageTransfer.maxWorldMapBytes
        )
        let files = WorldMapFiles(worldMapArchive: archive, setupJSON: setup)
        _ = try WorldMapFileValidation.validate(files, against: reference)
        return files
    }
}

enum WorldMapFileValidation {
    static func validate(
        _ files: WorldMapFiles,
        against reference: WorldMapReference
    ) throws -> WorldMapSetup {
        guard Int64(files.worldMapArchive.count) <= StorageTransfer.maxWorldMapBytes,
              Int64(files.setupJSON.count) <= StorageTransfer.maxWorldMapSetupBytes else {
            throw RepositoryError.fileTooLarge
        }
        guard StorageTransfer.sha256(files.setupJSON) == reference.setupSHA256.lowercased(),
              let setup = try? JSONDecoder().decode(WorldMapSetup.self, from: files.setupJSON),
              setup.matches(reference),
              setup.worldMapBytes == files.worldMapArchive.count,
              StorageTransfer.sha256(files.worldMapArchive) == setup.worldMapSHA256.lowercased() else {
            throw RepositoryError.integrityMismatch
        }
        return setup
    }
}
