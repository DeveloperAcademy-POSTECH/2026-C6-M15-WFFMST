import Foundation
import Observation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

private enum LocalFloorPlanHistoryEntry: Sendable {
    case edit(LocalEditAction)
}

enum FloorPlanProcessingStage: Equatable {
    case idle
    case normalizingImage
    case extractingMask
    case preparingPreview
    case replayingEdits

    var message: String? {
        switch self {
        case .idle: nil
        case .normalizingImage: "도면 이미지를 준비하는 중"
        case .extractingMask: "도면을 분석하고 벽을 추출하는 중"
        case .preparingPreview: "분석 결과와 미리보기를 준비하는 중"
        case .replayingEdits: "편집 결과를 계산하는 중"
        }
    }
}

enum FloorPlanMaskExtractionState: Equatable {
    case idle
    case running
    case succeeded
    case failed
}

@MainActor
@Observable
final class FloorPlanDraftStore {
    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "FloorPlanImport")
    private(set) var name = ""
    private(set) var step: FloorPlanRegistrationStep = .information
    private(set) var image: LocalImportedImage?
    private(set) var baseGrid: LocalObstacleGrid?
    private(set) var resolvedGrid: LocalObstacleGrid?
    private(set) var edits: [LocalEditAction] = []
    private(set) var outline: [LocalPlanPoint] = []
    private(set) var selection: [LocalPlanPoint] = []
    private(set) var pendingBrushStrokes: [LocalEditStroke] = []
    private(set) var scaleA: LocalPlanPoint?
    private(set) var scaleB: LocalPlanPoint?
    private(set) var distanceText = ""
    private(set) var tool: LocalCanvasTool = .move
    private(set) var editorMode: LocalFloorPlanEditorMode = .pen
    private(set) var normalizedDiameter = 0.006
    private(set) var processingStage: FloorPlanProcessingStage = .idle
    private(set) var maskExtractionState: FloorPlanMaskExtractionState = .idle
    private(set) var isDrawing = false
    private(set) var errorMessage: String?
    private(set) var maskPNGData: Data?
    private(set) var extractionAlgorithm: LocalWallExtractionAlgorithm = .v13
#if canImport(UIKit)
    private(set) var previewImage: UIImage?
    private(set) var maskImage: UIImage?
#endif
    @ObservationIgnored private let importer: any FloorPlanImporting
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var replayCache: LocalFloorPlanReplayCache?
    private var history: [LocalFloorPlanHistoryEntry] = []
    private var redoHistory: [LocalFloorPlanHistoryEntry] = []

    init(importer: any FloorPlanImporting = LocalFloorPlanImportService()) {
        self.importer = importer
    }

    deinit { work?.cancel() }

    var hasName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var editPointCount: Int {
        edits.reduce(into: 0) { count, edit in
            switch edit {
            case .stroke(let stroke): count += stroke.points.count
            case .region(let region): count += region.points.count
            }
        }
    }
    var canUndo: Bool { !selection.isEmpty || !pendingBrushStrokes.isEmpty || !history.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }
    var canApplySelection: Bool { selection.count >= 3 && !isProcessing }
    var canApplyBrush: Bool { !pendingBrushStrokes.isEmpty && !isProcessing && !isDrawing }
    var isProcessing: Bool { processingStage != .idle }
    var isImporting: Bool {
        processingStage == .normalizingImage
    }
    var activity: String { processingStage.message ?? "" }
    // Only same-image edit replay retains a preview; import/retry work stays visible.
    var isReplayingEdits: Bool { processingStage == .replayingEdits && maskPNGData != nil }
    var canContinueEditing: Bool {
        image != nil && resolvedGrid != nil && !outline.isEmpty && !isProcessing && !isDrawing
            && selection.isEmpty && pendingBrushStrokes.isEmpty
    }
    var scale: LocalPlanScale? {
        guard let scaleA, let scaleB,
              let meters = Double(distanceText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return LocalPlanScale(a: scaleA, b: scaleB, meters: meters)
    }
    var pixelsPerMeter: Double? {
        guard let scale, let image else { return nil }
        return try? LocalFloorPlanGeometry.validateScale(scale, width: image.width, height: image.height)
    }
    var hasValidScale: Bool { canContinueEditing && pixelsPerMeter != nil }
    var canRegister: Bool { step == .scaling && hasValidScale && hasName }
    var canSaveMaskEdit: Bool { step == .editing && hasValidScale && hasName }

    func begin() { reset() }
    func beginMaskEditing(_ snapshot: LocalFloorPlanSnapshot) {
        invalidateWork()
        clearImageState()
        let registration = snapshot.registration
        name = registration.name
        image = registration.image
        baseGrid = registration.resolvedGrid
        resolvedGrid = registration.resolvedGrid
        outline = registration.outline
        scaleA = registration.scale.a
        scaleB = registration.scale.b
        distanceText = String(registration.scale.meters)
        extractionAlgorithm = registration.extractionAlgorithm
        maskPNGData = snapshot.maskPNGData
        step = .editing
        editorMode = .pen
        tool = .pen
#if canImport(UIKit)
        previewImage = UIImage(data: registration.image.pngData)
        maskImage = UIImage(
            data: snapshot.maskPNGData,
            scale: 1 / CGFloat(registration.resolvedGrid.cellSizePixels)
        )
#endif
        errorMessage = nil
    }

    func reset() {
        invalidateWork()
        name = ""
        clearImageState()
        errorMessage = nil
    }
    func setName(_ value: String) { name = value }
    func setDistance(_ value: String) { distanceText = value }
    func setDrawing(_ value: Bool) { isDrawing = value }
    func setTool(_ value: LocalCanvasTool) {
        guard !isDrawing, !isProcessing else { return }
        tool = value
    }
    func setEditorMode(_ value: LocalFloorPlanEditorMode) {
        guard !isDrawing, !isProcessing else { return }
        editorMode = value
        tool = value == .pen ? .pen : .brush
        errorMessage = nil
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
        processingStage = .normalizingImage
        let token = generation
        let service = importer
        work = Task { [weak self] in
            do {
                let normalizedImage = try await service.normalize(url: url)
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }

                self.clearImageState()
                self.image = normalizedImage
#if canImport(UIKit)
                self.previewImage = UIImage(data: normalizedImage.pngData)
#endif
                self.processingStage = .extractingMask
                self.maskExtractionState = .running

                let result: LocalMaskExtractionResult
                do {
                    result = try await service.extractMask(from: normalizedImage)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Self.logger.error("AI wall extraction failed; using V13 fallback: \(error.localizedDescription, privacy: .public)")
                    result = try await service.extractFallbackMask(from: normalizedImage)
                }
                try Task.checkCancellation()
                guard self.generation == token else { return }

                self.processingStage = .preparingPreview
                let previewStart = ContinuousClock.now
                let outline = result.suggestedOutline.isEmpty
                    ? Self.fullImageOutline
                    : result.suggestedOutline
                // Prepare the complete replacement off-main, including its first preview.
                // The old draft remains usable if any of these steps fail or are cancelled.
                let preparation = Task.detached(priority: .userInitiated) {
                    var cache = try LocalFloorPlanReplayCache(base: result.baseGrid,
                        width: normalizedImage.width, height: normalizedImage.height)
                    let grid = try cache.resolve(edits: [], outline: outline)
                    try Task.checkCancellation()
                    let png = try LocalFloorPlanMaskRenderer.pngData(grid: grid)
                    return (cache, grid, png)
                }
                let (cache, grid, png) = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: { preparation.cancel() }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                Self.logDuration("preview", since: previewStart)

                self.baseGrid = result.baseGrid
                self.extractionAlgorithm = result.extractionAlgorithm
                self.resolvedGrid = grid
                self.outline = outline
                self.maskPNGData = png
                self.replayCache = cache
#if canImport(UIKit)
                self.previewImage = UIImage(data: normalizedImage.pngData)
                self.maskImage = UIImage(data: png, scale: 1 / CGFloat(grid.cellSizePixels))
#endif
                self.step = .editing
                self.editorMode = .pen
                self.tool = .pen
                self.maskExtractionState = .succeeded
                self.processingStage = .idle
                self.work = nil
            } catch {
                guard let self, self.generation == token else { return }
                if self.image != nil {
                    self.maskExtractionState = .failed
                }
                self.processingStage = .idle
                self.work = nil
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelProcessing() {
        invalidateWork()
        if image == nil { step = .information }
        errorMessage = nil
    }

    func stageBrushStroke(_ stroke: LocalEditStroke) {
        guard !isImporting else { return }
        guard step == .editing, image != nil, stroke.normalizedDiameter.isFinite,
              stroke.normalizedDiameter > 0, stroke.normalizedDiameter <= 0.1,
              !stroke.points.isEmpty, stroke.points.allSatisfy(\.isValid),
              edits.count + pendingBrushStrokes.count < 20_000,
              editPointCount + pendingBrushStrokes.reduce(stroke.points.count, { $0 + $1.points.count }) <= 250_000 else {
            errorMessage = "편집 입력이 유효하지 않거나 편집 한도를 초과했습니다."
            return
        }
        pendingBrushStrokes.append(stroke)
        errorMessage = nil
    }

    func applyPendingBrush(_ mode: LocalEditMode) {
        guard canApplyBrush else { return }
        let committed = pendingBrushStrokes.map {
            LocalEditAction.stroke(LocalEditStroke(mode: mode, points: $0.points,
                                                   normalizedDiameter: $0.normalizedDiameter))
        }
        pendingBrushStrokes = []
        for edit in committed {
            edits.append(edit)
            history.append(.edit(edit))
        }
        redoHistory = []
        recomputeMask(preservingPreview: true)
    }

    func applySelection(_ mode: LocalEditMode) {
        guard canApplySelection else { return }
        do {
            try LocalFloorPlanGeometry.validateRegion(selection)
            let edit = LocalEditAction.region(LocalEditRegion(mode: mode, points: selection))
            edits.append(edit)
            history.append(.edit(edit))
            redoHistory = []
            selection = []
            recomputeMask(preservingPreview: true)
        } catch { errorMessage = error.localizedDescription }
    }

    func undo() {
        guard !isDrawing, !isProcessing else { return }
        if !selection.isEmpty {
            selection.removeLast()
            return
        }
        if !pendingBrushStrokes.isEmpty {
            pendingBrushStrokes.removeLast()
            return
        }
        guard let entry = history.popLast() else { return }
        redoHistory.append(entry)
        switch entry {
        case .edit:
            _ = edits.popLast()
        }
        recomputeMask(preservingPreview: true)
    }

    func redo() {
        guard !isDrawing, !isProcessing, selection.isEmpty, pendingBrushStrokes.isEmpty,
              let entry = redoHistory.popLast() else { return }
        history.append(entry)
        switch entry {
        case .edit(let edit):
            edits.append(edit)
        }
        recomputeMask(preservingPreview: true)
    }

    func resetEdits() {
        guard !isDrawing else { return }
        edits = []
        pendingBrushStrokes = []
        selection = []
        history = []
        redoHistory = []
        recomputeMask(preservingPreview: true)
    }

    func placePoint(_ point: LocalPlanPoint) {
        guard point.isValid, !isProcessing else { return }
        switch tool {
        case .pen:
            guard selection.count < 512 else { errorMessage = "선택 영역의 꼭짓점은 최대 512개입니다."; return }
            selection.append(point)
        case .scaleA: scaleA = point; tool = .scaleB
        case .scaleB:
            if scaleB == nil { scaleB = point }
        default: return
        }
    }

    func moveScaleMarker(_ marker: LocalScaleMarker, to point: LocalPlanPoint) {
        guard step == .scaling, point.isValid, !isProcessing else { return }
        switch marker {
        case .a: scaleA = point
        case .b: scaleB = point
        }
    }

    func continueToScale() {
        guard canContinueEditing else { return }
        step = .scaling
        tool = .scaleA
        errorMessage = nil
    }
    func returnToEditing() {
        step = image == nil ? .information : .editing
        tool = editorMode == .pen ? .pen : .brush
    }

    func registration() -> LocalRegisteredFloorPlan? {
        guard canRegister, let image, let baseGrid, let resolvedGrid, let scale else { return nil }
        return LocalRegisteredFloorPlan(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            image: image, baseGrid: baseGrid, edits: edits, outline: outline, scale: scale,
            resolvedGrid: resolvedGrid, extractionAlgorithm: extractionAlgorithm)
    }

    func maskEditingRegistration() -> LocalRegisteredFloorPlan? {
        guard canSaveMaskEdit, let image, let baseGrid, let resolvedGrid, let scale else { return nil }
        return LocalRegisteredFloorPlan(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            image: image,
            baseGrid: baseGrid,
            edits: edits,
            outline: outline,
            scale: scale,
            resolvedGrid: resolvedGrid,
            extractionAlgorithm: extractionAlgorithm
        )
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
        processingStage = .replayingEdits
        errorMessage = nil
        let token = generation
        let currentEdits = edits
        let polygon = outline
        let previousCache = replayCache
        let processing = Task.detached(priority: .userInitiated) {
            var cache = try previousCache ?? LocalFloorPlanReplayCache(base: baseGrid, width: image.width, height: image.height)
            let grid = try cache.resolve(edits: currentEdits, outline: polygon)
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
                self.processingStage = .idle
                self.work = nil
            } catch {
                guard let self, self.generation == token else { return }
                self.processingStage = .idle
                self.work = nil
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func invalidateWork() {
        generation = UUID()
        work?.cancel()
        work = nil
        processingStage = .idle
    }

    private static func logDuration(_ stage: String, since start: ContinuousClock.Instant) {
#if DEBUG
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000
            + Double(duration.attoseconds) / 1_000_000_000_000_000
        logger.debug("stage=\(stage, privacy: .public) duration_ms=\(milliseconds, privacy: .public)")
#endif
    }

    private func clearImageState() {
        replayCache = nil
        step = .information
        image = nil
        baseGrid = nil
        extractionAlgorithm = .v13
        maskExtractionState = .idle
        resolvedGrid = nil
        edits = []
        outline = []
        selection = []
        pendingBrushStrokes = []
        history = []
        redoHistory = []
        scaleA = nil
        scaleB = nil
        distanceText = ""
        maskPNGData = nil
        tool = .move
        editorMode = .pen
        isDrawing = false
#if canImport(UIKit)
        previewImage = nil
        maskImage = nil
#endif
    }

    private static let fullImageOutline = [
        LocalPlanPoint(x: 0, y: 0),
        LocalPlanPoint(x: 1, y: 0),
        LocalPlanPoint(x: 1, y: 1),
        LocalPlanPoint(x: 0, y: 1),
    ]
}
