import CQBCore
import Foundation

nonisolated struct LocalWorldMapUpload: Sendable {
    let files: WorldMapFiles
    let reference: WorldMapReference
}

nonisolated enum LocalWorldMapFileBuilder {
    static func build(
        from draft: LocalWorldMapScanDraft,
        floorPlan: FloorPlanReference
    ) throws -> LocalWorldMapUpload {
        guard !draft.archive.isEmpty else {
            throw LocalFloorPlanError.invalid("저장할 WorldMap 데이터가 없습니다.")
        }
        let setup = WorldMapSetup(
            schemaVersion: 1,
            worldMapID: draft.id,
            createdAt: draft.createdAt,
            floorPlan: floorPlan,
            start: draft.start,
            correspondences: draft.correspondences,
            alignment: draft.alignment,
            compression: draft.compression,
            worldMapSHA256: LocalFloorPlanFileBuilder.sha256(draft.archive),
            worldMapBytes: draft.archive.count
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let setupJSON = try encoder.encode(setup)
        let reference = WorldMapReference(
            worldMapID: draft.id,
            setupSHA256: LocalFloorPlanFileBuilder.sha256(setupJSON),
            floorPlan: floorPlan
        )
        return LocalWorldMapUpload(
            files: WorldMapFiles(worldMapArchive: draft.archive, setupJSON: setupJSON),
            reference: reference
        )
    }

    static func rebind(
        _ files: WorldMapFiles,
        from reference: WorldMapReference,
        to floorPlan: FloorPlanReference,
        id: UUID = UUID(),
        createdAt: Date = .now
    ) throws -> LocalWorldMapUpload {
        guard reference.setupSHA256 == LocalFloorPlanFileBuilder.sha256(files.setupJSON) else {
            throw RepositoryError.integrityMismatch
        }
        let setup = try JSONDecoder().decode(WorldMapSetup.self, from: files.setupJSON)
        guard setup.matches(reference),
              setup.worldMapSHA256 == LocalFloorPlanFileBuilder.sha256(files.worldMapArchive),
              setup.worldMapBytes == files.worldMapArchive.count else {
            throw RepositoryError.integrityMismatch
        }
        let rebound = LocalWorldMapScanDraft(
            id: id,
            createdAt: createdAt,
            archive: files.worldMapArchive,
            start: setup.start,
            correspondences: setup.correspondences,
            alignment: setup.alignment,
            compression: setup.compression
        )
        return try build(from: rebound, floorPlan: floorPlan)
    }
}
