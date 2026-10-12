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
        try await StorageTransfer.uploadIfMissingOrMatching(
            files.imagePNG,
            to: StoragePaths.floorPlanImage(reference),
            contentType: "image/png"
        )
        try await StorageTransfer.uploadIfMissingOrMatching(
            files.resolvedMask,
            to: StoragePaths.floorPlanMask(reference),
            contentType: "application/octet-stream"
        )
        try await StorageTransfer.uploadIfMissingOrMatching(
            files.navigationMapJSON,
            to: StoragePaths.floorPlanNavigationMap(reference),
            contentType: "application/json"
        )
    }

    public func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        // 세 파일을 함께 받는다. 지도 정보의 지문이 맞지 않으면 나머지 다운로드는 취소된다.
        async let navigationMap = StorageTransfer.download(StoragePaths.floorPlanNavigationMap(reference))
        async let image = StorageTransfer.download(StoragePaths.floorPlanImage(reference))
        async let mask = StorageTransfer.download(StoragePaths.floorPlanMask(reference))
        let navigationMapData = try await navigationMap
        try verify(navigationMapData, against: reference)
        return FloorPlanFiles(
            imagePNG: try await image,
            navigationMapJSON: navigationMapData,
            resolvedMask: try await mask
        )
    }

    private func verify(_ navigationMap: Data, against reference: FloorPlanReference) throws {
        guard StorageTransfer.sha256(navigationMap) == reference.navigationSHA256.lowercased() else {
            throw RepositoryError.integrityMismatch
        }
    }
}
