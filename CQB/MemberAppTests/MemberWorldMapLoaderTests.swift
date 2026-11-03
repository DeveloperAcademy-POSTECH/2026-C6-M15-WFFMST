import Compression
import CQBCore
import CryptoKit
import XCTest
@testable import MemberApp

@MainActor
final class MemberWorldMapLoaderTests: XCTestCase {
    func testDecompressionAcceptsOutputExactlyAtConfiguredLimit() throws {
        let expected = Data(repeating: 0x5A, count: 64)
        let compressed = try lzfseCompress(expected)

        let actual = try MemberWorldMapLoader.decompress(compressed, maximumOutputBytes: expected.count)

        XCTAssertEqual(actual, expected)
    }

    func testDecompressionRejectsOutputOneByteAboveConfiguredLimit() throws {
        let oversized = Data(repeating: 0x5A, count: 65)
        let compressed = try lzfseCompress(oversized)

        XCTAssertThrowsError(try MemberWorldMapLoader.decompress(compressed, maximumOutputBytes: 64)) { error in
            guard case RepositoryError.integrityMismatch = error else {
                return XCTFail("Expected integrityMismatch, got \(error)")
            }
        }
    }

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

    private func lzfseCompress(_ data: Data) throws -> Data {
        let capacity = data.count + 256
        var output = Data(count: capacity)
        let count = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(dst, capacity, src, data.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard count > 0 else {
            throw RepositoryError.integrityMismatch
        }
        output.count = count
        return output
    }
}
