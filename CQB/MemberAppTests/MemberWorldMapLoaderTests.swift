import CQBCore
import CryptoKit
import Foundation
import XCTest
@testable import MemberApp

@MainActor
final class MemberWorldMapLoaderTests: XCTestCase {
    func testDecompressionAcceptsOutputExactlyAtConfiguredLimit() async throws {
        let expected = Data(repeating: 0x5A, count: 64)
        let actual = try MemberWorldMapLoader.decompress(try compress(expected), maximumOutputBytes: expected.count)
        XCTAssertEqual(actual, expected)
    }

    func testDecompressionRejectsOutputOneByteAboveConfiguredLimit() async throws {
        let compressed = try compress(Data(repeating: 0x5A, count: 65))
        XCTAssertThrowsError(try MemberWorldMapLoader.decompress(compressed, maximumOutputBytes: 64)) {
            XCTAssertEqual($0 as? MemberWorldMapLoadError, .decompressedSizeLimitExceeded)
        }
    }

    func testDecompressionAcceptsActual128MiBLimit() async throws {
        let count = 128 * 1_048_576
        let (compressed, expectedHash) = try largeArchive(count: count)
        let actual = try MemberWorldMapLoader.decompress(compressed)
        XCTAssertEqual(actual.count, count)
        XCTAssertEqual(WorldMapLoaderTestData.sha256(actual), expectedHash)
    }

    func testDecompressionRejectsActual128MiBPlusOneByte() async throws {
        let (compressed, _) = try largeArchive(count: 128 * 1_048_576 + 1)
        XCTAssertThrowsError(try MemberWorldMapLoader.decompress(compressed)) {
            XCTAssertEqual($0 as? MemberWorldMapLoadError, .decompressedSizeLimitExceeded)
        }
    }

    func testEmptyCorruptAndTruncatedDataAreRejected() async throws {
        let compressed = try compress(Data(repeating: 0x5A, count: 150_000))
        for invalid in [Data(), Data([1, 2, 3, 4]), Data(compressed.dropLast()), Data(compressed.dropLast(4))] {
            XCTAssertThrowsError(try MemberWorldMapLoader.decompress(invalid)) {
                XCTAssertEqual($0 as? MemberWorldMapLoadError, .invalidCompressedArchive)
            }
        }
    }

    func testCancelledTaskStopsDecompression() async throws {
        let compressed = try compress(Data(repeating: 1, count: 1_048_576))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try MemberWorldMapLoader.decompress(compressed)
        }
        do {
            _ = try await task.value
            XCTFail("취소된 작업은 압축 해제를 시작하면 안 됩니다.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testInvalidConfiguredOutputLimitIsRejected() async throws {
        let compressed = try compress(Data([1]))
        for limit in [0, -1, MemberWorldMapLoader.maximumDecompressedBytes + 1] {
            XCTAssertThrowsError(try MemberWorldMapLoader.decompress(compressed, maximumOutputBytes: limit)) {
                XCTAssertEqual($0 as? RepositoryError, .integrityMismatch)
            }
        }
    }

    func testFoundationLZFSEAndLegacyNoneRestoreIdenticalArchiveBytes() async throws {
        let original = Data(repeating: 0xA5, count: 150_000)
        for compression in [WorldMapCompression.none, .lzfse] {
            let stored = compression == .none ? original : try compress(original)
            let fixture = try WorldMapLoaderTestData.make(archive: stored, compression: compression)
            let (actual, setup) = try MemberWorldMapLoader.decodeArchive(files: fixture.files, reference: fixture.reference)
            XCTAssertEqual(actual, original)
            XCTAssertEqual(setup.compression, compression)
            XCTAssertEqual(setup.worldMapBytes, stored.count)
            XCTAssertEqual(setup.worldMapSHA256, WorldMapLoaderTestData.sha256(stored))
        }
    }

    func testBrokenArchiveHashIsRejectedBeforeDecompression() async throws {
        let compressed = try compress(Data(repeating: 42, count: 1_024))
        let fixture = try WorldMapLoaderTestData.make(archive: compressed)
        var changed = compressed
        changed[0] ^= 1
        for archive in [changed, compressed + Data([0])] {
            let files = WorldMapFiles(worldMapArchive: archive, setupJSON: fixture.files.setupJSON)
            XCTAssertThrowsError(try MemberWorldMapLoader.decodeArchive(files: files, reference: fixture.reference)) {
                XCTAssertEqual($0 as? RepositoryError, .integrityMismatch)
            }
        }
    }

    func testBrokenSetupHashIsRejectedBeforeJSONDecoding() async throws {
        let fixture = try WorldMapLoaderTestData.make(archive: Data([1]), compression: .none)
        let files = WorldMapFiles(worldMapArchive: fixture.files.worldMapArchive,
                                  setupJSON: fixture.files.setupJSON + Data([0]))
        XCTAssertThrowsError(try MemberWorldMapLoader.decodeArchive(files: files, reference: fixture.reference)) {
            XCTAssertEqual($0 as? RepositoryError, .integrityMismatch)
        }
    }

    func testMalformedSetupWithMatchingHashIsRejected() async throws {
        let fixture = try WorldMapLoaderTestData.make(archive: Data([1]), compression: .none)
        let malformed = Data("invalid-json".utf8)
        let reference = WorldMapReference(worldMapID: fixture.reference.worldMapID,
            setupSHA256: WorldMapLoaderTestData.sha256(malformed), floorPlan: fixture.reference.floorPlan)
        XCTAssertThrowsError(try MemberWorldMapLoader.decodeArchive(
            files: WorldMapFiles(worldMapArchive: Data([1]), setupJSON: malformed), reference: reference
        )) {
            XCTAssertEqual($0 as? RepositoryError, .integrityMismatch)
        }
    }

    func testSetupForDifferentFloorPlanIsRejected() async throws {
        let fixture = try WorldMapLoaderTestData.make(archive: Data([1]), compression: .none)
        let reference = WorldMapReference(worldMapID: fixture.reference.worldMapID,
            setupSHA256: fixture.reference.setupSHA256,
            floorPlan: FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "other"))
        XCTAssertThrowsError(try MemberWorldMapLoader.decodeArchive(files: fixture.files, reference: reference)) {
            XCTAssertEqual($0 as? RepositoryError, .integrityMismatch)
        }
    }

    func testWrongStoredByteCountAndUnsupportedSchemaAreRejected() async throws {
        for fixture in [
            try WorldMapLoaderTestData.make(archive: Data([1]), compression: .none, declaredBytes: 2),
            try WorldMapLoaderTestData.make(archive: Data([1]), compression: .none, schemaVersion: 2)
        ] {
            XCTAssertThrowsError(try MemberWorldMapLoader.decodeArchive(files: fixture.files, reference: fixture.reference)) {
                XCTAssertEqual($0 as? RepositoryError, .integrityMismatch)
            }
        }
    }

    func testStoredFileLimitsAreCheckedBeforeDecoding() async throws {
        let fixture = try WorldMapLoaderTestData.make(archive: Data([1]), compression: .none)
        for files in [
            WorldMapFiles(worldMapArchive: Data(count: 50 * 1_048_576 + 1), setupJSON: fixture.files.setupJSON),
            WorldMapFiles(worldMapArchive: Data([1]), setupJSON: Data(count: 1_048_576 + 1))
        ] {
            XCTAssertThrowsError(try MemberWorldMapLoader.decodeArchive(files: files, reference: fixture.reference)) {
                XCTAssertEqual($0 as? RepositoryError, .fileTooLarge)
            }
        }
    }

    func testInvalidARArchiveReportsRestorationFailure() async throws {
        let fixture = try WorldMapLoaderTestData.make(archive: Data("not-an-ar-archive".utf8), compression: .none)
        do {
            _ = try await MemberWorldMapLoader.load(files: fixture.files, reference: fixture.reference)
            XCTFail("유효하지 않은 아카이브는 복원에 실패해야 합니다.")
        } catch {
            XCTAssertEqual(error as? MemberWorldMapLoadError, .invalidArchive)
        }
    }

    private func compress(_ data: Data) throws -> Data {
        // InstructorApp과 같은 Foundation의 LZFSE 출력을 사용한다.
        try (data as NSData).compressed(using: .lzfse) as Data
    }

    private func largeArchive(count: Int) throws -> (Data, String) {
        let original = Data(repeating: 0x5A, count: count)
        return (try compress(original), WorldMapLoaderTestData.sha256(original))
    }
}

@MainActor
enum WorldMapLoaderTestData {
    static func make(
        archive: Data,
        compression: WorldMapCompression = .lzfse,
        declaredBytes: Int? = nil,
        schemaVersion: Int = 1
    ) throws -> (files: WorldMapFiles, reference: WorldMapReference) {
        let map = try BundledTrainingMapLoader.load()
        let template = PositioningTestData.setup(map)
        let setup = WorldMapSetup(schemaVersion: schemaVersion, worldMapID: template.worldMapID,
            createdAt: template.createdAt, floorPlan: template.floorPlan, start: template.start,
            correspondences: template.correspondences, alignment: template.alignment,
            compression: compression, worldMapSHA256: sha256(archive), worldMapBytes: declaredBytes ?? archive.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let setupJSON = try encoder.encode(setup)
        return (
            WorldMapFiles(worldMapArchive: archive, setupJSON: setupJSON),
            WorldMapReference(worldMapID: setup.worldMapID, setupSHA256: sha256(setupJSON), floorPlan: map.reference)
        )
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
