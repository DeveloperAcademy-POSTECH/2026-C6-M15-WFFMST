import CQBCore
import Foundation
import Testing
@testable import InstructorApp

struct LocalPixelWallDetectorTests {
    @Test
    func detectsSupportedHorizontalAndVerticalWallRuns() throws {
        let width = 128
        let height = 128
        var pixels = [UInt8](repeating: 255, count: width * height * 4)

        func drawPixel(x: Int, y: Int) {
            let offset = (y * width + x) * 4
            pixels[offset] = 20
            pixels[offset + 1] = 20
            pixels[offset + 2] = 20
            pixels[offset + 3] = 255
        }

        for y in 30...34 {
            for x in 12...112 { drawPixel(x: x, y: y) }
        }
        for x in 70...74 {
            for y in 12...112 { drawPixel(x: x, y: y) }
        }

        let grid = try LocalPixelWallDetector.grid(rgba: pixels, width: width, height: height)

        #expect(grid.cellSizePixels == 2)
        #expect(grid.columns == 64)
        #expect(grid.rows == 64)
        #expect(grid.blocked.contains(1))
        #expect(grid.blocked[(32 / 2) * grid.columns + 40 / 2] == 1)
        #expect(grid.blocked[(60 / 2) * grid.columns + 72 / 2] == 1)
    }

    @Test
    func rejectsMismatchedPixelBuffer() {
        #expect(throws: LocalFloorPlanError.self) {
            try LocalPixelWallDetector.grid(
                rgba: [UInt8](repeating: 255, count: 12),
                width: 10,
                height: 10
            )
        }
    }
}

@MainActor
struct PixelWallExtractionFlowTests {
    @Test
    func worldMapScanStartsWhilePixelExtractionIsRunning() async {
        let gate = MaskExtractionGate()
        let scanner = ParallelScanStub()
        let store = FloorPlanDraftStore(
            importer: SuspendedPixelImporter(gate: gate),
            worldMapScanner: scanner
        )

        store.importImage(from: URL(fileURLWithPath: "/tmp/parallel-pixel-plan.png"))
        await waitUntil { store.maskExtractionState == .running }

        store.setName("병렬 추출 테스트")
        store.continueToWorldMapAlignment()
        store.placePoint(.init(x: 0.1, y: 0.1))
        store.placePoint(.init(x: 0.2, y: 0.1))
        store.placePoint(.init(x: 0.6, y: 0.6))
        await store.startWorldMapScan()

        #expect(store.step == .scanning)
        #expect(store.maskExtractionState == .running)
        #expect(scanner.didStart)

        await gate.open()
        await waitUntil { store.maskExtractionState == .succeeded }

        #expect(store.extractionAlgorithm == .v13)
        #expect(store.resolvedGrid != nil)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        attempts: Int = 2_000
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("기대한 비동기 상태에 도달하지 못했습니다.")
    }
}

private actor MaskExtractionGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private struct SuspendedPixelImporter: FloorPlanImporting {
    let gate: MaskExtractionGate

    func normalize(url: URL) async throws -> LocalImportedImage {
        LocalImportedImage(
            pngData: Data(),
            width: 4,
            height: 4,
            fileName: url.lastPathComponent
        )
    }

    func extractMask(from image: LocalImportedImage) async throws -> LocalMaskExtractionResult {
        await gate.wait()
        return LocalMaskExtractionResult(
            baseGrid: LocalObstacleGrid(
                columns: 2,
                rows: 2,
                cellSizePixels: 2,
                blocked: [1, 0, 0, 1]
            ),
            suggestedOutline: [
                .init(x: 0, y: 0),
                .init(x: 1, y: 0),
                .init(x: 1, y: 1),
                .init(x: 0, y: 1),
            ],
            extractionAlgorithm: .v13
        )
    }
}

@MainActor
private final class ParallelScanStub: WorldMapScanning {
    var previewSession: AnyObject { self }
    var onFrameUpdate: ((LocalWorldMapFrameState) -> Void)?
    private(set) var didStart = false

    func start() async throws { didStart = true }
    func captureCurrentPose() -> LocalWorldMapPoseCaptureResult {
        .captured(ARPose(x: 0, y: 1.5, z: 0, forwardX: 1, forwardZ: 0))
    }
    func makeWorldMapArchive() async throws -> Data { Data() }
    func stop() {}
}
