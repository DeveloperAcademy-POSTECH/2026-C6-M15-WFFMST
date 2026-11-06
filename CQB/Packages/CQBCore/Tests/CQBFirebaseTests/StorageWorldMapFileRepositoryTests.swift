import CQBCore
import Foundation
import Testing
@testable import CQBFirebase

private let worldMapFloorPlan = FloorPlanReference(
    floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
    navigationSHA256: "navigation-sha"
)

private func worldMapFixture() throws -> (WorldMapReference, WorldMapFiles) {
    let archive = Data("world-map-archive".utf8)
    let setup = WorldMapSetup(
        schemaVersion: 1,
        worldMapID: UUID(uuidString: "00000000-0000-0000-0000-000000000802")!,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        floorPlan: worldMapFloorPlan,
        start: WorldMapStart(
            pose: ARPose(x: 1, y: 0, z: 2, forwardX: 0, forwardZ: -1),
            planPoint: NormalizedPoint(x: 0.2, y: 0.3),
            directionPoint: NormalizedPoint(x: 0.2, y: 0.2)
        ),
        correspondences: [],
        alignment: WorldMapAlignment(
            rotationDegrees: 0,
            pixelsPerMeter: 40,
            translation: ImagePoint(x: 100, y: 200),
            rmsErrorMeters: 0.1,
            algorithmVersion: "similarity-v1"
        ),
        compression: .none,
        worldMapSHA256: StorageTransfer.sha256(archive),
        worldMapBytes: archive.count
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let setupJSON = try encoder.encode(setup)
    let reference = WorldMapReference(
        worldMapID: setup.worldMapID,
        setupSHA256: StorageTransfer.sha256(setupJSON),
        floorPlan: worldMapFloorPlan
    )
    return (reference, WorldMapFiles(worldMapArchive: archive, setupJSON: setupJSON))
}

@Test("WorldMap 파일 묶음의 두 단계 해시와 도면 짝을 검증한다")
func validatesWorldMapFiles() throws {
    let (reference, files) = try worldMapFixture()
    let setup = try WorldMapFileValidation.validate(files, against: reference)
    #expect(setup.worldMapID == reference.worldMapID)
    #expect(setup.floorPlan == reference.floorPlan)
}

@Test("WorldMap archive 바이트가 바뀌면 무결성 오류다")
func rejectsChangedWorldMapArchive() throws {
    let (reference, files) = try worldMapFixture()
    let changed = WorldMapFiles(worldMapArchive: files.worldMapArchive + Data([0]), setupJSON: files.setupJSON)
    #expect(throws: RepositoryError.integrityMismatch) {
        try WorldMapFileValidation.validate(changed, against: reference)
    }
}

@Test("다른 도면의 WorldMap 참조는 거부한다")
func rejectsMismatchedWorldMapFloorPlan() throws {
    let (reference, files) = try worldMapFixture()
    let other = WorldMapReference(
        worldMapID: reference.worldMapID,
        setupSHA256: reference.setupSHA256,
        floorPlan: FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "other")
    )
    #expect(throws: RepositoryError.integrityMismatch) {
        try WorldMapFileValidation.validate(files, against: other)
    }
}
