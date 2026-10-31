import CQBCore
import CryptoKit
import Foundation
import XCTest
@testable import InstructorApp

final class CachedFloorPlanFileRepositoryTests: XCTestCase {
    func testRepeatedDownloadUsesMemoryThenDiskWithoutAnotherRemoteRequest() async throws {
        let fixture = makeFixture(seed: 1)
        let directory = temporaryDirectory()
        let remote = FloorPlanRemoteStub(result: .success(fixture.files))
        let firstCache = makeCache(remote: remote, directory: directory)

        _ = try await firstCache.download(fixture.reference)
        _ = try await firstCache.download(fixture.reference)
        let initialDownloadCount = await remote.downloadCount
        XCTAssertEqual(initialDownloadCount, 1)

        let offline = FloorPlanRemoteStub(result: .failure(TestError.offline))
        let restoredCache = makeCache(remote: offline, directory: directory)
        let restored = try await restoredCache.download(fixture.reference)

        XCTAssertEqual(restored.imagePNG, fixture.files.imagePNG)
        let offlineDownloadCount = await offline.downloadCount
        XCTAssertEqual(offlineDownloadCount, 0)
    }

    func testConcurrentRequestsShareOneRemoteDownload() async throws {
        let fixture = makeFixture(seed: 2)
        let remote = FloorPlanRemoteStub(result: .success(fixture.files), delay: .milliseconds(50))
        let cache = makeCache(remote: remote, directory: temporaryDirectory())

        async let first = cache.download(fixture.reference)
        async let second = cache.download(fixture.reference)
        _ = try await (first, second)

        let downloadCount = await remote.downloadCount
        XCTAssertEqual(downloadCount, 1)
    }

    func testCorruptedDiskEntryIsDiscardedAndDownloadedAgain() async throws {
        let fixture = makeFixture(seed: 3)
        let directory = temporaryDirectory()
        let initialRemote = FloorPlanRemoteStub(result: .success(fixture.files))
        let initialCache = makeCache(remote: initialRemote, directory: directory)
        _ = try await initialCache.download(fixture.reference)

        let entry = directory.appendingPathComponent(CachedFloorPlanFileRepository.cacheKey(for: fixture.reference))
        try Data("corrupted".utf8).write(to: entry.appendingPathComponent("original.png"), options: .atomic)

        let recoveryRemote = FloorPlanRemoteStub(result: .success(fixture.files))
        let recoveredCache = makeCache(remote: recoveryRemote, directory: directory)
        let recovered = try await recoveredCache.download(fixture.reference)

        XCTAssertEqual(recovered.imagePNG, fixture.files.imagePNG)
        let recoveryDownloadCount = await recoveryRemote.downloadCount
        XCTAssertEqual(recoveryDownloadCount, 1)
    }

    func testOfflineMissReportsRemoteFailure() async {
        let fixture = makeFixture(seed: 4)
        let remote = FloorPlanRemoteStub(result: .failure(TestError.offline))
        let cache = makeCache(remote: remote, directory: temporaryDirectory())

        do {
            _ = try await cache.download(fixture.reference)
            XCTFail("캐시 미적중 상태의 오프라인 오류가 전달되어야 합니다.")
        } catch {
            XCTAssertEqual(error as? TestError, .offline)
        }
    }

    func testInvalidRemoteFilesAreNotCached() async {
        let fixture = makeFixture(seed: 5)
        let invalid = FloorPlanFiles(
            imagePNG: Data("different".utf8),
            navigationMapJSON: fixture.files.navigationMapJSON,
            resolvedMask: fixture.files.resolvedMask
        )
        let directory = temporaryDirectory()
        let remote = FloorPlanRemoteStub(result: .success(invalid))
        let cache = makeCache(remote: remote, directory: directory)

        do {
            _ = try await cache.download(fixture.reference)
            XCTFail("무결성이 깨진 파일은 거부되어야 합니다.")
        } catch {
            XCTAssertEqual(error as? RepositoryError, .integrityMismatch)
        }

        let entry = directory.appendingPathComponent(CachedFloorPlanFileRepository.cacheKey(for: fixture.reference))
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.path))
    }

    private func makeCache(remote: FloorPlanRemoteStub, directory: URL) -> CachedFloorPlanFileRepository {
        CachedFloorPlanFileRepository(
            remote: remote,
            configuration: .init(
                directory: directory,
                diskLimitBytes: 10 * 1_024 * 1_024,
                memoryLimitBytes: 10 * 1_024 * 1_024
            )
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CachedFloorPlanFileRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeFixture(seed: UInt8) -> (files: FloorPlanFiles, reference: FloorPlanReference) {
        let floorPlanID = UUID()
        let image = Data([seed, seed &+ 1, seed &+ 2])
        let mask = Data([0, 1, 0, 1])
        let manifest = FloorPlanManifest(
            schemaVersion: 1,
            floorPlanID: floorPlanID,
            coordinateSystem: "image-pixel-top-left",
            imageWidth: 2,
            imageHeight: 2,
            imageSHA256: sha256(image),
            scale: MapScale(a: ImagePoint(x: 0, y: 0), b: ImagePoint(x: 1, y: 0), meters: 1),
            indoorOutline: [],
            navigationGrid: NavigationGridDescriptor(
                columns: 2,
                rows: 2,
                cellSizePixels: 1,
                encoding: "uint8-row-major",
                freeValue: 0,
                blockedValue: 1,
                outsideIsBlocked: true,
                maskSHA256: sha256(mask)
            ),
            extractionAlgorithmVersion: "test",
            rasterizationVersion: 2,
            manuallyReviewed: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let navigationMap = try! encoder.encode(manifest)
        return (
            FloorPlanFiles(imagePNG: image, navigationMapJSON: navigationMap, resolvedMask: mask),
            FloorPlanReference(floorPlanID: floorPlanID, navigationSHA256: sha256(navigationMap))
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private actor FloorPlanRemoteStub: FloorPlanFileRepository {
    private(set) var downloadCount = 0
    private let result: Result<FloorPlanFiles, Error>
    private let delay: Duration?

    init(result: Result<FloorPlanFiles, Error>, delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }

    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        downloadCount += 1
        if let delay { try await Task.sleep(for: delay) }
        return try result.get()
    }
}

private enum TestError: Error, Equatable {
    case offline
}
