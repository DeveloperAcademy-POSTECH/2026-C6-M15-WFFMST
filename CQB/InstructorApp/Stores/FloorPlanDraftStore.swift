import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class FloorPlanDraftStore {
    private(set) var name = ""
    private(set) var step: FloorPlanRegistrationStep = .information
    private(set) var image: LocalImportedImage?
    private(set) var baseGrid: LocalObstacleGrid?
    private(set) var resolvedGrid: LocalObstacleGrid?
    private(set) var strokes: [LocalEditStroke] = []
    private(set) var outline: [LocalPlanPoint] = []
    private(set) var outlineConfirmed = false
    private(set) var scaleA: LocalPlanPoint?
    private(set) var scaleB: LocalPlanPoint?
    private(set) var distanceText = ""
    private(set) var tool: LocalCanvasTool = .move
    private(set) var normalizedDiameter = 0.006
    private(set) var isProcessing = false
    private(set) var isImporting = false
    private(set) var isDrawing = false
    private(set) var activity = ""
    private(set) var errorMessage: String?
    private(set) var reviewed = false
    private(set) var maskPNGData: Data?
#if canImport(UIKit)
    private(set) var previewImage: UIImage?
    private(set) var maskImage: UIImage?
#endif
    @ObservationIgnored private let importer: any FloorPlanImporting
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var replayCache: LocalFloorPlanReplayCache?

    init(importer: any FloorPlanImporting = LocalFloorPlanImportService()) {
        self.importer = importer
    }

    deinit { work?.cancel() }

    var hasName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    // Only same-image edit replay retains a preview; import/outline/retry work stays visible.
    var isReplayingEdits: Bool { isProcessing && !isImporting && maskPNGData != nil }
    var canContinueEditing: Bool { hasName && image != nil && resolvedGrid != nil && outlineConfirmed && !isProcessing && !isDrawing }
    var scale: LocalPlanScale? {
        guard let scaleA, let scaleB,
              let meters = Double(distanceText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return LocalPlanScale(a: scaleA, b: scaleB, meters: meters)
    }
    var pixelsPerMeter: Double? {
        guard let scale, let image else { return nil }
        return try? LocalFloorPlanGeometry.validateScale(scale, width: image.width, height: image.height)
    }
    var canReview: Bool { canContinueEditing && pixelsPerMeter != nil }
    var canRegister: Bool { step == .reviewing && canReview && reviewed }

    func begin() { reset() }
    func reset() {
        invalidateWork()
        name = ""
        clearImageState()
        errorMessage = nil
    }
    func setName(_ value: String) { name = value; reviewed = false }
    func setDistance(_ value: String) { distanceText = value; reviewed = false }
    func setReviewed(_ value: Bool) { reviewed = value }
    func setDrawing(_ value: Bool) { isDrawing = value }
    func setTool(_ value: LocalCanvasTool) {
        guard !isDrawing, !isProcessing else { return }
        tool = value
    }
    func setBrushDiameter(_ value: Double) {
        guard !isDrawing, value.isFinite else { return }
        normalizedDiameter = min(0.05, max(0.001, value))
    }
    func reportImportFailure(_ error: Error) {
        let cocoaError = error as NSError
        guard !(error is CancellationError),
              !(cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError) else { return }
        errorMessage = error.localizedDescription
    }

    func importImage(from url: URL) {
        invalidateWork()
        errorMessage = nil
        isProcessing = true
        isImporting = true
        activity = "이미지 정규화 및 장애물 자동 추출 중"
        let token = generation
        let service = importer
        // Prepare the complete replacement off-main, including its first preview.
        // The old draft remains usable if any of these steps fail or are cancelled.
        let preparation = Task.detached(priority: .userInitiated) {
            let result = try await service.process(url: url)
            try Task.checkCancellation()
            var cache = try LocalFloorPlanReplayCache(base: result.baseGrid,
                width: result.image.width, height: result.image.height)
            let grid = try cache.resolve(strokes: [], outline: [])
            let png = try LocalFloorPlanMaskRenderer.pngData(grid: grid)
            return (result, cache, grid, png)
        }
        work = Task { [weak self] in
            do {
                let (result, cache, grid, png) = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: { preparation.cancel() }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.clearImageState()
                self.image = result.image
                self.baseGrid = result.baseGrid
                self.resolvedGrid = grid
                self.maskPNGData = png
                self.replayCache = cache
#if canImport(UIKit)
                self.previewImage = UIImage(data: result.image.pngData)
                self.maskImage = UIImage(data: png, scale: 1 / CGFloat(grid.cellSizePixels))
#endif
                self.step = .editing
                self.tool = .move
                self.isProcessing = false
                self.isImporting = false
                self.work = nil
            } catch {
                guard let self, self.generation == token else { return }
                self.isProcessing = false
                self.isImporting = false
                self.work = nil
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelProcessing() {
        invalidateWork()
        if image == nil { step = .information }
        errorMessage = "처리를 취소했습니다. 파일을 다시 선택하거나 미리보기를 다시 계산할 수 있습니다."
    }

    func appendStroke(_ stroke: LocalEditStroke) {
        guard !isImporting else { return }
        guard step == .editing, image != nil, stroke.normalizedDiameter.isFinite,
              stroke.normalizedDiameter > 0, stroke.normalizedDiameter <= 0.1,
              !stroke.points.isEmpty, stroke.points.allSatisfy(\.isValid),
              strokes.count < 20_000,
              strokes.reduce(stroke.points.count, { $0 + $1.points.count }) <= 250_000 else {
            errorMessage = "편집 입력이 유효하지 않거나 편집 한도를 초과했습니다."
            return
        }
        strokes.append(stroke)
        reviewed = false
        recomputeMask(preservingPreview: true)
    }
    func undoStroke() {
        guard !isDrawing, !strokes.isEmpty else { return }
        strokes.removeLast()
        reviewed = false
        recomputeMask(preservingPreview: true)
    }
    func resetEdits() {
        guard !isDrawing else { return }
        strokes = []
        reviewed = false
        recomputeMask(preservingPreview: true)
    }
    func placePoint(_ point: LocalPlanPoint) {
        guard point.isValid, !isProcessing else { return }
        switch tool {
        case .outline:
            guard outline.count < 512 else { errorMessage = "외곽 꼭짓점은 최대 512개입니다."; return }
            let hadConfirmedOutline = outlineConfirmed
            outline.append(point)
            outlineConfirmed = false
            if hadConfirmedOutline { refreshMask() }
        case .scaleA: scaleA = point; tool = .scaleB
        case .scaleB: scaleB = point
        default: return
        }
        reviewed = false
    }
    func resetOutline() {
        outline = []
        outlineConfirmed = false
        reviewed = false
        tool = .outline
        refreshMask()
    }
    func undoOutlinePoint() {
        guard !outline.isEmpty else { return }
        outline.removeLast()
        outlineConfirmed = false
        refreshMask()
    }
    func confirmOutline() {
        do {
            try LocalFloorPlanGeometry.validateOutline(outline)
            outlineConfirmed = true
            tool = .move
            refreshMask()
        } catch { errorMessage = error.localizedDescription }
    }
    func continueToScale() {
        guard canContinueEditing else { return }
        step = .scaling
        tool = .scaleA
        errorMessage = nil
    }
    func showReview() {
        guard canReview else { errorMessage = "서로 10px 이상 떨어진 두 점과 0 초과 1000m 이하의 거리를 입력해주세요."; return }
        step = .reviewing
        tool = .move
        reviewed = false
        errorMessage = nil
    }
    func returnToEditing() { step = .editing; tool = .move; reviewed = false }
    func returnToScale() { step = .scaling; tool = .scaleA; reviewed = false }

    func registration() -> LocalRegisteredFloorPlan? {
        guard canRegister, let image, let baseGrid, let resolvedGrid, let scale else { return nil }
        return LocalRegisteredFloorPlan(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            image: image, baseGrid: baseGrid, strokes: strokes, outline: outline, scale: scale, resolvedGrid: resolvedGrid)
    }

    // Outline/image changes must not display a previously confirmed boundary.
    func refreshMask() {
        recomputeMask(preservingPreview: false)
    }

    // During stroke replay, retain only the last visual preview to prevent flashing.
    // The authoritative grid is always invalidated immediately, so it cannot be registered.
    private func recomputeMask(preservingPreview: Bool) {
        guard let image, let baseGrid else { return }
        invalidateWork()
        resolvedGrid = nil
        if !preservingPreview {
            maskPNGData = nil
#if canImport(UIKit)
            maskImage = nil
#endif
        }
        isProcessing = true
        activity = "편집 결과 계산 중"
        errorMessage = nil
        let token = generation
        let edits = strokes
        let polygon = outlineConfirmed ? outline : []
        let previousCache = replayCache
        let processing = Task.detached(priority: .userInitiated) {
            var cache = try previousCache ?? LocalFloorPlanReplayCache(base: baseGrid, width: image.width, height: image.height)
            let grid = try cache.resolve(strokes: edits, outline: polygon)
            try Task.checkCancellation()
            let png = try LocalFloorPlanMaskRenderer.pngData(grid: grid)
            return (grid, png, cache)
        }
        work = Task { [weak self] in
            do {
                let (grid, png, cache) = try await withTaskCancellationHandler {
                    try await processing.value
                } onCancel: { processing.cancel() }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.resolvedGrid = grid
                self.replayCache = cache
                self.maskPNGData = png
#if canImport(UIKit)
                self.maskImage = UIImage(data: png, scale: 1 / CGFloat(grid.cellSizePixels))
#endif
                self.isProcessing = false
                self.work = nil
            } catch {
                guard let self, self.generation == token else { return }
                self.isProcessing = false
                self.work = nil
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func invalidateWork() {
        generation = UUID()
        work?.cancel()
        work = nil
        isProcessing = false
        isImporting = false
    }
    private func clearImageState() {
        replayCache = nil
        step = .information
        image = nil
        baseGrid = nil
        resolvedGrid = nil
        strokes = []
        outline = []
        outlineConfirmed = false
        scaleA = nil
        scaleB = nil
        distanceText = ""
        maskPNGData = nil
        reviewed = false
        tool = .move
        isDrawing = false
#if canImport(UIKit)
        previewImage = nil
        maskImage = nil
#endif
    }
}
