//
//  StorageFloorPlanFileRepository.swift
//  CQB
//

import CQBCore
import Foundation

/// `floorPlans/{floorPlanID}/` 아래 도면 파일 3개를 다룬다.
public struct StorageFloorPlanFileRepository: FloorPlanFileRepository {
    public init() {}

    public func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {
        try verify(files.navigationMapJSON, against: reference)
        try await StorageTransfer.upload(files.imagePNG, to: StoragePaths.floorPlanImage(reference), contentType: "image/png")
        try await StorageTransfer.upload(files.resolvedMask, to: StoragePaths.floorPlanMask(reference), contentType: "application/octet-stream")
        try await StorageTransfer.upload(files.navigationMapJSON, to: StoragePaths.floorPlanNavigationMap(reference), contentType: "application/json")
    }

    public func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        let navigationMap = try await StorageTransfer.download(StoragePaths.floorPlanNavigationMap(reference))
        try verify(navigationMap, against: reference)
        return FloorPlanFiles(
            imagePNG: try await StorageTransfer.download(StoragePaths.floorPlanImage(reference)),
            navigationMapJSON: navigationMap,
            resolvedMask: try await StorageTransfer.download(StoragePaths.floorPlanMask(reference))
        )
    }

    private func verify(_ navigationMap: Data, against reference: FloorPlanReference) throws {
        guard StorageTransfer.sha256(navigationMap) == reference.navigationSHA256.lowercased() else {
            throw RepositoryError.integrityMismatch
        }
    }
}
