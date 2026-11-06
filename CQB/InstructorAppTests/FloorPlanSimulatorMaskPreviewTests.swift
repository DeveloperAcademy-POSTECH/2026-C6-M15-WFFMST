#if DEBUG && targetEnvironment(simulator)
import Foundation
import Testing
@testable import InstructorApp

@MainActor
struct FloorPlanSimulatorMaskPreviewTests {
    @Test
    func previewsExtractedMaskWithoutAllowingRegistration() async throws {
        let importer = SimulatorMaskPreviewImporter()
        let store = FloorPlanDraftStore(importer: importer)

        store.importImage(from: URL(fileURLWithPath: "/tmp/simulator-mask-preview.png"))
        while store.processingStage != .idle {
            await Task.yield()
        }
        store.setName("Simulator 마스크 검증")
        store.continueToWorldMapAlignment()

        #expect(store.canPreviewExtractedMask)
        store.previewExtractedMask()

        #expect(store.step == .editing)
        #expect(store.worldMapScanDraft() == nil)
        #expect(!store.canRegister)
    }
}

private struct SimulatorMaskPreviewImporter: FloorPlanImporting {
    private let grid = LocalObstacleGrid(
        columns: 2,
        rows: 2,
        cellSizePixels: 2,
        blocked: [1, 0, 0, 1]
    )

    func normalize(url: URL) async throws -> LocalImportedImage {
        LocalImportedImage(
            pngData: Data(),
            width: 4,
            height: 4,
            fileName: url.lastPathComponent
        )
    }

    func extractMask(from image: LocalImportedImage) async throws -> LocalMaskExtractionResult {
        result
    }

    private var result: LocalMaskExtractionResult {
        LocalMaskExtractionResult(
            baseGrid: grid,
            suggestedOutline: [
                LocalPlanPoint(x: 0, y: 0),
                LocalPlanPoint(x: 1, y: 0),
                LocalPlanPoint(x: 1, y: 1),
                LocalPlanPoint(x: 0, y: 1),
            ],
            extractionAlgorithm: .v13
        )
    }
}
#endif
