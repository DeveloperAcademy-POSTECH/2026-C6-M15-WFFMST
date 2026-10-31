import CQBCore
import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import InstructorApp

final class CachedFloorPlanFileRepositoryTests: XCTestCase {
    func testRepeatedDownloadUsesMemoryThenDiskWithoutAnotherRemoteRequest() async throws {
        let fixture = try makeFixture(seed: 1)
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
        let fixture = try makeFixture(seed: 2)
        let remote = FloorPlanRemoteStub(result: .success(fixture.files), delay: .milliseconds(50))
        let cache = makeCache(remote: remote, directory: temporaryDirectory())

        async let first = cache.download(fixture.reference)
        async let second = cache.download(fixture.reference)
        _ = try await (first, second)

        let downloadCount = await remote.downloadCount
        XCTAssertEqual(downloadCount, 1)
    }

    func testCorruptedDiskEntryIsDiscardedAndDownloadedAgain() async throws {
        let fixture = try makeFixture(seed: 3)
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

    func testOfflineMissReportsRemoteFailure() async throws {
        let fixture = try makeFixture(seed: 4)
        let remote = FloorPlanRemoteStub(result: .failure(TestError.offline))
        let cache = makeCache(remote: remote, directory: temporaryDirectory())

        do {
            _ = try await cache.download(fixture.reference)
            XCTFail("캐시 미적중 상태의 오프라인 오류가 전달되어야 합니다.")
        } catch {
            XCTAssertEqual(error as? TestError, .offline)
        }
    }

    func testRemoteFilesMustPassDetailLoaderValidationBeforeCaching() async throws {
        let fixture = try makeFixture(seed: 5)
        let invalidFixtures = try [
            ("PNG 디코딩", replacing(fixture, imagePNG: Data([1, 2, 3]))),
            ("이미지 크기", replacing(fixture, imageWidth: 15)),
            ("mask 값", replacing(fixture, mask: Data([0, 2, 0, 1]))),
            ("outside 정책", replacing(fixture, outsideIsBlocked: false)),
            ("축척", replacing(
                fixture,
                scale: MapScale(a: ImagePoint(x: 0, y: 0), b: ImagePoint(x: 1, y: 0), meters: 1)
            )),
            ("외곽선", replacing(fixture, indoorOutline: [])),
            ("추출 알고리즘", replacing(fixture, extractionAlgorithmVersion: "unsupported"))
        ]

        for (label, invalid) in invalidFixtures {
            await assertFilesAreNotCached(invalid, label: label)
        }
    }

    func testDiskHitRemovesAbandonedStagingDirectory() async throws {
        let fixture = try makeFixture(seed: 6)
        let directory = temporaryDirectory()
        let online = FloorPlanRemoteStub(result: .success(fixture.files))
        _ = try await makeCache(remote: online, directory: directory).download(fixture.reference)

        let staging = directory.appendingPathComponent(".staging-interrupted", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_024).write(to: staging.appendingPathComponent("partial"))

        let offline = FloorPlanRemoteStub(result: .failure(TestError.offline))
        let restored = try await makeCache(remote: offline, directory: directory).download(fixture.reference)

        XCTAssertEqual(restored.imagePNG, fixture.files.imagePNG)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        let offlineDownloadCount = await offline.downloadCount
        XCTAssertEqual(offlineDownloadCount, 0)
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

    private func makeFixture(seed: UInt8) throws -> (files: FloorPlanFiles, reference: FloorPlanReference) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
            .image { context in
                UIColor(
                    red: CGFloat(seed) / 255,
                    green: CGFloat(seed &+ 1) / 255,
                    blue: CGFloat(seed &+ 2) / 255,
                    alpha: 1
                ).setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
        let grid = LocalObstacleGrid(
            columns: 2,
            rows: 2,
            cellSizePixels: 8,
            blocked: [0, 1, 0, 1]
        )
        let registration = LocalRegisteredFloorPlan(
            id: UUID(),
            name: "캐시 테스트 도면",
            image: LocalImportedImage(
                pngData: try XCTUnwrap(image.pngData()),
                width: 16,
                height: 16,
                fileName: "fixture.png"
            ),
            baseGrid: grid,
            edits: [],
            outline: [
                LocalPlanPoint(x: 0, y: 0),
                LocalPlanPoint(x: 1, y: 0),
                LocalPlanPoint(x: 1, y: 1),
                LocalPlanPoint(x: 0, y: 1)
            ],
            scale: LocalPlanScale(
                a: LocalPlanPoint(x: 0, y: 0.5),
                b: LocalPlanPoint(x: 1, y: 0.5),
                meters: 4
            ),
            resolvedGrid: grid,
            extractionAlgorithm: .v13
        )
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        return (upload.files, upload.reference)
    }

    private func replacing(
        _ fixture: (files: FloorPlanFiles, reference: FloorPlanReference),
        imagePNG: Data? = nil,
        imageWidth: Int? = nil,
        mask: Data? = nil,
        outsideIsBlocked: Bool? = nil,
        scale: MapScale? = nil,
        indoorOutline: [NormalizedPoint]? = nil,
        extractionAlgorithmVersion: String? = nil
    ) throws -> (files: FloorPlanFiles, reference: FloorPlanReference) {
        let original = try JSONDecoder().decode(FloorPlanManifest.self, from: fixture.files.navigationMapJSON)
        let updatedImage = imagePNG ?? fixture.files.imagePNG
        let updatedMask = mask ?? fixture.files.resolvedMask
        let originalGrid = original.navigationGrid
        let updatedGrid = NavigationGridDescriptor(
            columns: originalGrid.columns,
            rows: originalGrid.rows,
            cellSizePixels: originalGrid.cellSizePixels,
            encoding: originalGrid.encoding,
            freeValue: originalGrid.freeValue,
            blockedValue: originalGrid.blockedValue,
            outsideIsBlocked: outsideIsBlocked ?? originalGrid.outsideIsBlocked,
            maskSHA256: sha256(updatedMask)
        )
        let manifest = FloorPlanManifest(
            schemaVersion: original.schemaVersion,
            floorPlanID: original.floorPlanID,
            coordinateSystem: original.coordinateSystem,
            imageWidth: imageWidth ?? original.imageWidth,
            imageHeight: original.imageHeight,
            imageSHA256: sha256(updatedImage),
            scale: scale ?? original.scale,
            indoorOutline: indoorOutline ?? original.indoorOutline,
            navigationGrid: updatedGrid,
            extractionAlgorithmVersion: extractionAlgorithmVersion ?? original.extractionAlgorithmVersion,
            rasterizationVersion: original.rasterizationVersion,
            manuallyReviewed: original.manuallyReviewed
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let navigationMap = try encoder.encode(manifest)
        return (
            FloorPlanFiles(imagePNG: updatedImage, navigationMapJSON: navigationMap, resolvedMask: updatedMask),
            FloorPlanReference(floorPlanID: manifest.floorPlanID, navigationSHA256: sha256(navigationMap))
        )
    }

    private func assertFilesAreNotCached(
        _ fixture: (files: FloorPlanFiles, reference: FloorPlanReference),
        label: String
    ) async {
        let directory = temporaryDirectory()
        let remote = FloorPlanRemoteStub(result: .success(fixture.files))
        let cache = makeCache(remote: remote, directory: directory)

        do {
            _ = try await cache.download(fixture.reference)
            XCTFail("\(label)이 유효하지 않은 파일은 거부되어야 합니다.")
        } catch {
            // 세부 오류보다 캐시에 진입하지 않는 것이 이 테스트의 계약이다.
        }

        let entry = directory.appendingPathComponent(
            CachedFloorPlanFileRepository.cacheKey(for: fixture.reference)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.path), label)
        let downloadCount = await remote.downloadCount
        XCTAssertEqual(downloadCount, 1, label)
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
