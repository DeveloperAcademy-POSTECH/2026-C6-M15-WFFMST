import CQBCore
import CryptoKit
import XCTest
@testable import MemberApp

@MainActor
final class MemberWorldMapLoaderTests: XCTestCase {
    func testBrokenArchiveHashIsRejectedBeforeARKitDecoding() async throws {
        let map = try BundledTrainingMapLoader.load()
        let setup = PositioningTestData.setup(map)
        let setupJSON = try JSONEncoder().encode(setup)
        let hash = SHA256.hash(data: setupJSON).map { String(format: "%02x", $0) }.joined()
        let reference = WorldMapReference(worldMapID: setup.worldMapID, setupSHA256: hash, floorPlan: map.reference)
        let files = WorldMapFiles(worldMapArchive: Data(), setupJSON: setupJSON)
        do {
            _ = try await MemberWorldMapLoader.load(files: files, reference: reference)
            XCTFail("Expected integrityMismatch")
        } catch {
            guard case RepositoryError.integrityMismatch = error else {
                return XCTFail("Expected integrityMismatch, got \(error)")
            }
        }
    }

    func testSetupForDifferentFloorPlanIsRejected() async throws {
        let map = try BundledTrainingMapLoader.load()
        let setup = PositioningTestData.setup(map)
        let data = try JSONEncoder().encode(setup)
        let reference = WorldMapReference(worldMapID: setup.worldMapID,
            setupSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            floorPlan: FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "other"))
        do {
            _ = try await MemberWorldMapLoader.load(files: WorldMapFiles(worldMapArchive: Data(), setupJSON: data), reference: reference)
            XCTFail("Expected integrityMismatch")
        } catch {
            guard case RepositoryError.integrityMismatch = error else {
                return XCTFail("Expected integrityMismatch, got \(error)")
            }
        }
    }
}
