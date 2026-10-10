import Foundation

/// Intentionally ignores cancellation until the test releases a result. This models a slow external decoder.
private actor ControlledImporter: FloorPlanImporting {
    private var pending: [String: CheckedContinuation<LocalExtractionResult, Error>] = [:]
    private(set) var finished = 0
    func process(url: URL) async throws -> LocalExtractionResult {
        defer { finished += 1 }
        return try await withCheckedThrowingContinuation { pending[url.lastPathComponent] = $0 }
    }
    func has(_ name: String) -> Bool { pending[name] != nil }
    func succeed(_ name: String) {
        pending.removeValue(forKey: name)?.resume(returning: LocalExtractionResult(
            image: LocalImportedImage(pngData: Data([1]), width: 100, height: 80, fileName: name),
            baseGrid: LocalObstacleGrid(columns: 50, rows: 40, cellSizePixels: 2,
                blocked: [UInt8](repeating: 0, count: 2_000))))
    }
    func fail(_ name: String) {
        pending.removeValue(forKey: name)?.resume(throwing: LocalFloorPlanError.invalid("추출 실패 테스트"))
    }
}

@main
@MainActor
enum FloorPlanRegistrationChecks {
    static func main() async throws {
        try await fullRegistration()
        try await staleImportAndReplacement()
        try await errorsCancellationAndLifetime()
        print("PASS: Registration lifecycle, validation, snapshot/preview equality, stale results, cancellation, deallocation")
    }

    static func fullRegistration() async throws {
        let service = ControlledImporter()
        let draft = FloorPlanDraftStore(importer: service)
        let store = InstructorStore(floorPlans: [], floorPlanDraft: draft)
        store.openFloorPlanCreation()
        draft.setName("  새 도면  ")
        try await load("first.png", draft: draft, service: service)
        precondition(draft.step == .editing && !draft.canContinueEditing)
        draft.setTool(.outline)
        draft.placePoint(point(0.1, 0.1))
        draft.placePoint(point(0.9, 0.1))
        draft.confirmOutline()
        precondition(!draft.outlineConfirmed && draft.errorMessage != nil, "two-point outline must fail")
        draft.placePoint(point(0.9, 0.9))
        draft.placePoint(point(0.1, 0.9))
        draft.confirmOutline()
        precondition(draft.isProcessing && !draft.isReplayingEdits, "outline calculation must retain visible progress")
        try await idle(draft)
        precondition(draft.canContinueEditing)
        let stroke = LocalEditStroke(mode: .block, points: [point(0.3, 0.3), point(0.6, 0.3)], normalizedDiameter: 0.03)
        let previousPreview = draft.maskPNGData
        draft.appendStroke(stroke)
        precondition(draft.isReplayingEdits, "stroke replay uses quiet processing presentation")
        precondition(draft.resolvedGrid == nil && !draft.canContinueEditing, "old preview must invalidate synchronously")
        precondition(draft.maskPNGData == previousPreview && previousPreview != nil,
                     "keep the last visual mask while replaying a stroke, without keeping a registerable grid")
        try await idle(draft)
        precondition(!draft.isReplayingEdits)
        precondition(draft.maskPNGData != previousPreview && draft.resolvedGrid != nil, "replace preview after replay succeeds")
        let editedPreview = draft.maskPNGData
        draft.undoStroke()
        precondition(draft.maskPNGData == editedPreview && draft.resolvedGrid == nil)
        try await idle(draft)
        precondition(draft.maskPNGData == previousPreview)
        draft.appendStroke(stroke)
        try await idle(draft)
        draft.continueToScale()
        draft.placePoint(point(0.2, 0.2))
        draft.placePoint(point(0.2, 0.2))
        draft.setDistance("10")
        precondition(!draft.canReview, "identical scale points must fail")
        draft.placePoint(point(0.8, 0.2))
        for invalid in ["", "0", "-1", "nan", "inf", "1001", "text"] {
            draft.setDistance(invalid)
            precondition(!draft.canReview, "invalid distance accepted: \(invalid)")
        }
        draft.setDistance("10")
        precondition(abs((draft.pixelsPerMeter ?? 0) - 6) < 1e-9)
        draft.showReview()
        precondition(!draft.canRegister && draft.registration() == nil, "explicit review required")
        draft.setReviewed(true)
        draft.setDrawing(true)
        precondition(!draft.canRegister, "in-progress gesture must block register")
        draft.setDrawing(false)
        let snapshot = draft.registration()!
        precondition(snapshot.name == "새 도면" && snapshot.resolvedGrid == draft.resolvedGrid)
        precondition(snapshot.strokes == [stroke] && snapshot.outline == draft.outline)
        draft.reportImportFailure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        draft.reportImportFailure(CancellationError())
        precondition(draft.errorMessage == nil && draft.canRegister && draft.registration()?.image == snapshot.image)
        precondition(draft.strokes == snapshot.strokes && draft.outline == snapshot.outline && draft.scale == snapshot.scale,
                     "picker cancellation must preserve the complete reviewed draft")
        precondition(snapshot.resolvedGrid.blocked[0] == 1, "outside outline must be blocked")
        let expectedPreview = try LocalFloorPlanMaskRenderer.pngData(grid: snapshot.resolvedGrid)
        precondition(draft.maskPNGData == expectedPreview)
        store.registerFloorPlan()
        precondition(store.phase == .floorPlanList && store.floorPlans.count == 1)
        precondition(store.selectedFloorPlan?.registeredPlan?.resolvedGrid == snapshot.resolvedGrid)
        precondition(store.selectedFloorPlan?.registeredPlan?.image == snapshot.image)
        precondition(draft.image == nil && draft.name.isEmpty && draft.strokes.isEmpty && draft.scale == nil)
        store.registerFloorPlan()
        precondition(store.floorPlans.count == 1, "duplicate register must not append")
        store.openSessionCreation()
        precondition(store.canCreateSession && store.selectedFloorPlan?.name == "새 도면")
        store.openFloorPlanCreation()
        precondition(draft.step == .information && draft.outline.isEmpty && !draft.reviewed)
        draft.setName("취소할 입력")
        store.goBack()
        precondition(store.phase == .floorPlanList && draft.name.isEmpty)
    }

    static func staleImportAndReplacement() async throws {
        let service = ControlledImporter()
        let draft = FloorPlanDraftStore(importer: service)
        draft.setName("유지할 이름")
        draft.importImage(from: url("old.png"))
        precondition(draft.isProcessing && !draft.isReplayingEdits, "initial extraction must retain visible progress")
        try await wait { await service.has("old.png") }
        draft.importImage(from: url("new.png"))
        try await wait { await service.has("new.png") }
        await service.succeed("new.png")
        try await idle(draft)
        await service.succeed("old.png")
        try await wait { await service.finished == 2 }
        for _ in 0..<5 { await Task.yield() }
        precondition(draft.image?.fileName == "new.png", "stale successful result must not overwrite current image")
        draft.appendStroke(LocalEditStroke(mode: .block, points: [point(0.5, 0.5)], normalizedDiameter: 0.02))
        try await idle(draft)
        draft.setTool(.outline)
        for p in [point(0, 0), point(1, 0), point(1, 1), point(0, 1)] { draft.placePoint(p) }
        draft.confirmOutline()
        try await idle(draft)
        draft.continueToScale()
        draft.placePoint(point(0.1, 0.1))
        draft.placePoint(point(0.8, 0.1))
        draft.setDistance("7")
        draft.showReview()
        draft.setReviewed(true)
        precondition(draft.canRegister)
        let previous = draft.registration()!
        let previousPNG = draft.maskPNGData
        draft.importImage(from: url("broken-replacement.png"))
        precondition(draft.isImporting && !draft.isReplayingEdits && !draft.canRegister)
        try await wait { await service.has("broken-replacement.png") }
        await service.fail("broken-replacement.png")
        try await idle(draft)
        precondition(draft.canRegister && draft.image == previous.image && draft.strokes == previous.strokes)
        precondition(draft.outline == previous.outline && draft.scale == previous.scale && draft.maskPNGData == previousPNG,
                     "failed replacement must preserve the complete reviewed draft")
        draft.importImage(from: url("cancel-replacement.png"))
        try await wait { await service.has("cancel-replacement.png") }
        draft.cancelProcessing()
        await service.succeed("cancel-replacement.png")
        try await wait { await service.finished == 4 }
        for _ in 0..<5 { await Task.yield() }
        precondition(draft.canRegister && draft.image == previous.image && draft.strokes == previous.strokes)
        precondition(draft.outline == previous.outline && draft.scale == previous.scale && draft.maskPNGData == previousPNG,
                     "cancelled replacement must preserve draft and ignore late success")
        draft.importImage(from: url("replacement.png"))
        precondition(draft.image == previous.image && draft.resolvedGrid == previous.resolvedGrid && draft.maskPNGData == previousPNG)
        precondition(draft.strokes == previous.strokes && draft.outline == previous.outline && draft.scale == previous.scale)
        precondition(draft.name == "유지할 이름" && !draft.canRegister)
        try await wait { await service.has("replacement.png") }
        await service.succeed("replacement.png")
        try await idle(draft)
        precondition(draft.image?.fileName == "replacement.png" && !draft.canContinueEditing)
        precondition(draft.strokes.isEmpty && draft.outline.isEmpty && draft.scale == nil && !draft.reviewed,
                     "only successful replacement resets old edits")
        draft.setTool(.outline)
        for p in [point(0.1, 0.1), point(0.9, 0.1), point(0.9, 0.9), point(0.1, 0.9)] { draft.placePoint(p) }
        draft.confirmOutline()
        try await idle(draft)
        precondition(draft.outlineConfirmed && draft.resolvedGrid?.blocked[0] == 1)
        draft.setTool(.outline)
        draft.placePoint(point(0.05, 0.5))
        precondition(!draft.outlineConfirmed && draft.resolvedGrid == nil && draft.maskPNGData == nil,
            "changing confirmed outline must immediately invalidate stale constrained preview")
        try await idle(draft)
        precondition(draft.resolvedGrid?.blocked[0] == 0 && !draft.canContinueEditing,
            "unconfirmed edited outline must show unconstrained base while registration stays blocked")
        draft.refreshMask()
        draft.cancelProcessing()
        precondition(draft.resolvedGrid == nil && !draft.canRegister && !draft.isProcessing)
        draft.refreshMask()
        try await idle(draft)
        precondition(draft.resolvedGrid != nil, "cancelled mask calculation must be retryable")
        let block = LocalEditStroke(mode: .block, points: [point(0.2, 0.2), point(0.8, 0.8)], normalizedDiameter: 0.03)
        let open = LocalEditStroke(mode: .open, points: block.points, normalizedDiameter: 0.02)
        draft.appendStroke(block)
        draft.appendStroke(open) // cancels the first calculation before its cache commits
        try await idle(draft)
        let full = try LocalFloorPlanGeometry.resolve(base: draft.baseGrid!, width: draft.image!.width,
            height: draft.image!.height, strokes: draft.strokes, outline: [])
        precondition(draft.resolvedGrid == full, "cancelled incremental work must not corrupt the next cache")
        draft.undoStroke()
        draft.cancelProcessing()
        draft.refreshMask()
        try await idle(draft)
        let afterUndo = try LocalFloorPlanGeometry.resolve(base: draft.baseGrid!, width: draft.image!.width,
            height: draft.image!.height, strokes: draft.strokes, outline: [])
        precondition(draft.resolvedGrid == afterUndo, "retry after cancelled undo must use the current history")
    }

    static func errorsCancellationAndLifetime() async throws {
        let service = ControlledImporter()
        let draft = FloorPlanDraftStore(importer: service)
        draft.importImage(from: url("fail.png"))
        try await wait { await service.has("fail.png") }
        await service.fail("fail.png")
        try await idle(draft)
        precondition(draft.errorMessage == "추출 실패 테스트" && draft.image == nil && !draft.canRegister)
        draft.importImage(from: url("cancel.png"))
        try await wait { await service.has("cancel.png") }
        draft.cancelProcessing()
        precondition(!draft.isProcessing && draft.step == .information && !draft.canRegister)
        await service.succeed("cancel.png")
        try await wait { await service.finished == 2 }
        for _ in 0..<5 { await Task.yield() }
        precondition(draft.image == nil, "cancelled import cannot revive draft")
        draft.importImage(from: url("reset.png"))
        try await wait { await service.has("reset.png") }
        draft.reset()
        await service.fail("reset.png")
        try await wait { await service.finished == 3 }
        for _ in 0..<5 { await Task.yield() }
        precondition(draft.errorMessage == nil && draft.image == nil, "stale error cannot pollute reset draft")

        var disposable: FloorPlanDraftStore? = FloorPlanDraftStore(importer: service)
        weak let weakDraft = disposable
        disposable?.importImage(from: url("release.png"))
        try await wait { await service.has("release.png") }
        disposable = nil
        precondition(weakDraft == nil, "pending importer must not strongly retain draft store")
        await service.succeed("release.png")
        try await wait { await service.finished == 4 }
    }

    private static func load(_ name: String, draft: FloorPlanDraftStore, service: ControlledImporter) async throws {
        draft.importImage(from: url(name))
        try await wait { await service.has(name) }
        await service.succeed(name)
        try await idle(draft)
        precondition(draft.image != nil && draft.resolvedGrid != nil)
    }
    static func idle(_ draft: FloorPlanDraftStore) async throws {
        try await wait { !draft.isProcessing }
    }
    static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw LocalFloorPlanError.invalid("Test timed out") }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    static func url(_ name: String) -> URL { URL(fileURLWithPath: "/virtual/\(name)") }
    static func point(_ x: Double, _ y: Double) -> LocalPlanPoint { LocalPlanPoint(x: x, y: y) }
}
