import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

private enum LocalFloorPlanHistoryEntry: Sendable {
    case edit(LocalEditAction)
    case outline(previous: [LocalPlanPoint], next: [LocalPlanPoint])
}

@MainActor
@Observable
final class FloorPlanDraftStore {
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
    private(set) var isProcessing = false
    private(set) var isImporting = false
    private(set) var isDrawing = false
    private(set) var activity = ""
    private(set) var errorMessage: String?
    private(set) var maskPNGData: Data?
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
    // Only same-image edit replay retains a preview; import/outline/retry work stays visible.
    var isReplayingEdits: Bool { isProcessing && !isImporting && maskPNGData != nil }
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

    func begin() { reset() }
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
            let grid = try cache.resolve(edits: [], outline: [])
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
                self.editorMode = .pen
                self.tool = .pen
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

    func applyOutlineSelection() {
        guard canApplySelection else { return }
        do {
            try LocalFloorPlanGeometry.validateOutline(selection)
            let previous = outline
            let next = selection
            outline = next
            selection = []
            history.append(.outline(previous: previous, next: next))
            redoHistory = []
            refreshMask()
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
        case .outline(let previous, _):
            outline = previous
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
        case .outline(_, let next):
            outline = next
        }
        recomputeMask(preservingPreview: true)
    }

    func resetEdits() {
        guard !isDrawing else { return }
        edits = []
        pendingBrushStrokes = []
        selection = []
        history.removeAll { entry in
            if case .edit = entry { return true }
            return false
        }
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

    func resetOutline() {
        guard !outline.isEmpty else { return }
        let previous = outline
        outline = []
        history.append(.outline(previous: previous, next: []))
        redoHistory = []
        refreshMask()
    }

    func undoOutlinePoint() {
        guard !selection.isEmpty else { return }
        selection.removeLast()
    }

    func confirmOutline() {
        applyOutlineSelection()
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
            image: image, baseGrid: baseGrid, edits: edits, outline: outline, scale: scale, resolvedGrid: resolvedGrid)
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
}
