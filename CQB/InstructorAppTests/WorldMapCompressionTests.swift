import Compression
import CQBCore
import Foundation
import Security
import XCTest
@testable import InstructorApp

@MainActor
final class WorldMapCompressionTests: XCTestCase {
    func testSavingScanStoresCompressedDraftAndMetadata() async throws {
        let original = Data(repeating: 42, count: 1_048_576)
        let scanner = CompressionScanStub(archive: original)
        let store = try await readyToSave(scanner: scanner)

        await store.saveWorldMap()

        let draft = try XCTUnwrap(store.worldMapScanDraft())
        XCTAssertEqual(draft.compression, .lzfse)
        XCTAssertLessThan(draft.archive.count, original.count)
        XCTAssertEqual(try decodeLikeMember(draft.archive, capacity: original.count + 1), original)
        XCTAssertTrue(scanner.stopped)
        XCTAssertFalse(store.isSavingWorldMap)
        XCTAssertNil(store.worldMapSaveErrorMessage)
        let upload = try LocalWorldMapFileBuilder.build(from: draft, floorPlan: floorPlan)
        let setup = try JSONDecoder().decode(WorldMapSetup.self, from: upload.files.setupJSON)
        XCTAssertEqual(setup.compression, .lzfse)
        XCTAssertEqual(setup.worldMapBytes, draft.archive.count)
        XCTAssertEqual(setup.worldMapSHA256, LocalFloorPlanFileBuilder.sha256(draft.archive))
        XCTAssertEqual(upload.reference.setupSHA256, LocalFloorPlanFileBuilder.sha256(upload.files.setupJSON))

        let rebound = try LocalWorldMapFileBuilder.rebind(upload.files, from: upload.reference, to: floorPlan)
        XCTAssertEqual(rebound.files.worldMapArchive, draft.archive)
        let reboundSetup = try JSONDecoder().decode(WorldMapSetup.self, from: rebound.files.setupJSON)
        XCTAssertEqual(reboundSetup.compression, .lzfse)
    }

    func testOriginalLargerThan50MBIsAllowedWhenCompressedFits() async throws {
        let original = Data(repeating: 0, count: 51 * 1_024 * 1_024)
        let compressed = try await LocalWorldMapArchiveCompressor.compress(original)
        XCTAssertLessThan(compressed.count, LocalUploadSizeValidator.maximumWorldMapBytes)
        XCTAssertEqual(try decodeLikeMember(compressed, capacity: original.count + 1), original)
    }

    func testUploadSizeBoundariesAndErrorContainExactSizes() async throws {
        for (fileName, maximum) in [
            ("도면 이미지", LocalUploadSizeValidator.maximumFileBytes),
            ("공간 스캔 파일", LocalUploadSizeValidator.maximumWorldMapBytes),
            ("공간 스캔 설정 파일", LocalUploadSizeValidator.maximumWorldMapSetupBytes)
        ] {
            try LocalUploadSizeValidator.validate(byteCount: maximum, fileName: fileName, maximumBytes: maximum)
            XCTAssertThrowsError(try LocalUploadSizeValidator.validate(
                byteCount: maximum + 1, fileName: fileName, maximumBytes: maximum, isCompressed: true
            )) { error in
                let sizeError = error as? LocalUploadFileSizeError
                XCTAssertEqual(sizeError?.actualBytes, maximum + 1)
                XCTAssertEqual(sizeError?.maximumBytes, maximum)
                XCTAssertTrue(error.localizedDescription.contains("압축 후 용량"))
                XCTAssertTrue(error.localizedDescription.contains("\(maximum + 1)바이트"))
                XCTAssertTrue(error.localizedDescription.contains("\(maximum)바이트"))
            }
        }
    }

    func testEmptyArchiveShowsSaveErrorWithoutAdvancing() async throws {
        let scanner = CompressionScanStub(archive: Data())
        let store = try await readyToSave(scanner: scanner)
        await store.saveWorldMap()
        XCTAssertEqual(store.step, .scanning)
        XCTAssertNil(store.worldMapScanDraft())
        XCTAssertNotNil(store.worldMapSaveErrorMessage)
        XCTAssertFalse(store.isSavingWorldMap)
        XCTAssertFalse(scanner.stopped)
        store.dismissWorldMapSaveError()
        XCTAssertNil(store.worldMapSaveErrorMessage)
    }

    func testOversizedCompressedScanShowsActualSizeAndDoesNotAdvance() async throws {
        // 압축하기 어려운 입력으로, 압축 후에도 실제 50MB 한도를 넘는 경로를 검사한다.
        var original = Data(count: 51 * 1_024 * 1_024)
        let status = original.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        XCTAssertEqual(status, errSecSuccess)
        let scanner = CompressionScanStub(archive: original)
        let store = try await readyToSave(scanner: scanner)
        await store.saveWorldMap()
        let message = try XCTUnwrap(store.worldMapSaveErrorMessage)
        XCTAssertTrue(message.contains("압축 후 용량:"))
        XCTAssertTrue(message.contains("최대 허용 용량: 50.0MB (52428800바이트)"))
        XCTAssertNil(store.worldMapScanDraft())
        XCTAssertEqual(store.step, .scanning)
        XCTAssertFalse(store.isSavingWorldMap)
        XCTAssertFalse(scanner.stopped)
    }

    func testArchiveBeyondMemberRestorationLimitIsRejected() async throws {
        let bytes = LocalWorldMapArchiveCompressor.maximumRestorableArchiveBytes + 1
        do {
            _ = try await LocalWorldMapArchiveCompressor.compress(Data(count: bytes))
            XCTFail("대원 앱이 복원할 수 없는 원본은 저장하면 안 됩니다.")
        } catch let error as LocalWorldMapCompressionError {
            guard case .restorationLimitExceeded(let actualBytes) = error else {
                return XCTFail("원본의 복원 한도 초과 오류여야 합니다.")
            }
            XCTAssertEqual(actualBytes, bytes)
        }
    }

    func testResetWhileArchivingDoesNotSaveLateResult() async throws {
        let scanner = CompressionScanStub(archive: Data(repeating: 1, count: 1_024))
        scanner.suspendsArchive = true
        let store = try await readyToSave(scanner: scanner)
        let save = Task { await store.saveWorldMap() }
        for _ in 0..<100 where scanner.continuation == nil {
            await Task.yield()
        }
        let continuation = try XCTUnwrap(scanner.continuation)
        store.reset()
        continuation.resume(returning: scanner.archive)
        scanner.continuation = nil
        await save.value
        XCTAssertNil(store.worldMapScanDraft())
        XCTAssertNil(store.worldMapSaveErrorMessage)
        XCTAssertFalse(store.isSavingWorldMap)
        XCTAssertEqual(store.step, .information)
    }

    private var floorPlan: FloorPlanReference {
        FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "test-plan")
    }

    private func decodeLikeMember(_ data: Data, capacity: Int) throws -> Data {
        var output = Data(count: capacity)
        let count = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZFSE
                )
            }
        }
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(count, capacity)
        return output.prefix(count)
    }

    private func readyToSave(scanner: CompressionScanStub) async throws -> FloorPlanDraftStore {
        let store = FloorPlanDraftStore(worldMapScanner: scanner)
        let grid = LocalObstacleGrid(columns: 2, rows: 2, cellSizePixels: 8, blocked: [0, 0, 0, 0])
        let registration = LocalRegisteredFloorPlan(
            id: UUID(), name: "압축 테스트",
            image: LocalImportedImage(pngData: Data(), width: 16, height: 16, fileName: "plan.png"),
            baseGrid: grid, edits: [],
            outline: [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1), .init(x: 0, y: 1)],
            scale: LocalPlanScale(a: .init(x: 0, y: 0.5), b: .init(x: 1, y: 0.5), meters: 4),
            resolvedGrid: grid, extractionAlgorithm: .v13
        )
        store.beginMaskEditing(LocalFloorPlanSnapshot(registration: registration, maskPNGData: Data()))
        store.continueToWorldMapAlignment()
        store.placePoint(.init(x: 0, y: 0.5))
        store.placePoint(.init(x: 1, y: 0.5))
        store.placePoint(.init(x: 1, y: 0.5))
        await store.startWorldMapScan()
        scanner.onFrameUpdate?(.init(mapping: .mapped, trackingMessage: "추적 정상"))
        store.captureWorldMapStart()
        scanner.pose = ARPose(x: 4, y: 1.5, z: 0, forwardX: 1, forwardZ: 0)
        XCTAssertEqual(store.captureScanCheckpoint(at: 0), .captured)
        XCTAssertTrue(store.canSaveWorldMap)
        return store
    }
}

@MainActor
private final class CompressionScanStub: WorldMapScanning {
    let archive: Data
    var pose = ARPose(x: 0, y: 1.5, z: 0, forwardX: 1, forwardZ: 0)
    var previewSession: AnyObject { self }
    var onFrameUpdate: ((LocalWorldMapFrameState) -> Void)?
    var stopped = false
    var suspendsArchive = false
    var continuation: CheckedContinuation<Data, Error>?

    init(archive: Data) { self.archive = archive }
    func start() async throws { stopped = false }
    func currentPose() throws -> ARPose { pose }
    func makeWorldMapArchive() async throws -> Data {
        if suspendsArchive {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return archive
    }
    func stop() { stopped = true }
}
