import CQBCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private actor ControlledImporter: FloorPlanImporting {
    private var pending: [String: CheckedContinuation<LocalExtractionResult, Error>] = [:]

    func process(url: URL) async throws -> LocalExtractionResult {
        try await withCheckedThrowingContinuation { pending[url.lastPathComponent] = $0 }
    }

    func has(_ name: String) -> Bool { pending[name] != nil }

    func succeed(_ name: String, suggestedOutline: [LocalPlanPoint] = []) {
        pending.removeValue(forKey: name)?.resume(returning: LocalExtractionResult(
            image: LocalImportedImage(
                pngData: Data([1, 2, 3]),
                width: 100,
                height: 80,
                fileName: name
            ),
            baseGrid: LocalObstacleGrid(
                columns: 50,
                rows: 40,
                cellSizePixels: 2,
                blocked: [UInt8](repeating: 0, count: 2_000)
            ),
            suggestedOutline: suggestedOutline
        ))
    }

    func fail(_ name: String, error: Error) {
        pending.removeValue(forKey: name)?.resume(throwing: error)
    }
}

private actor ControlledFloorPlanFileRepository: FloorPlanFileRepository {
    private var failuresRemaining: Int
    private var references: [FloorPlanReference] = []
    private var uploadedFiles: [FloorPlanFiles] = []

    init(failures: Int = 0) {
        failuresRemaining = failures
    }

    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {
        uploadedFiles.append(files)
        references.append(reference)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw URLError(.notConnectedToInternet)
        }
    }

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        throw RepositoryError.notFound
    }

    func uploads() -> [(FloorPlanReference, FloorPlanFiles)] {
        Array(zip(references, uploadedFiles))
    }

    func failNextUpload() { failuresRemaining = 1 }
}

@main
@MainActor
enum FloorPlanRegistrationChecks {
    static func main() async throws {
        try await checkImportLifecycle()

        let importer = ControlledImporter()
        let draft = FloorPlanDraftStore(importer: importer)
        let repository = ControlledFloorPlanFileRepository(failures: 1)
        let catalog = DemoFloorPlanCatalogRepository()
        let store = InstructorStore(
            floorPlans: [],
            floorPlanDraft: draft,
            floorPlanFileRepository: repository,
            floorPlanCatalogRepository: catalog
        )

        store.loadFloorPlans()
        store.openFloorPlanCreation()
        let stroke = try await prepareDraft(draft, importer: importer)

        let snapshot = try require(draft.registration(), "등록 가능한 도면 스냅샷 필요")
        precondition(snapshot.name == "새 도면")
        precondition(snapshot.edits == [.stroke(stroke)])

        let expectedUpload = try LocalFloorPlanFileBuilder.build(from: snapshot)
        let manifest = try JSONDecoder().decode(
            FloorPlanManifest.self,
            from: expectedUpload.files.navigationMapJSON
        )
        precondition(expectedUpload.files.imagePNG == snapshot.image.pngData)
        precondition(expectedUpload.files.resolvedMask == Data(snapshot.resolvedGrid.blocked))
        precondition(manifest.floorPlanID == snapshot.id)
        precondition(manifest.imageSHA256 == LocalFloorPlanFileBuilder.sha256(expectedUpload.files.imagePNG))
        precondition(manifest.navigationGrid.maskSHA256
            == LocalFloorPlanFileBuilder.sha256(expectedUpload.files.resolvedMask))
        precondition(expectedUpload.reference.navigationSHA256
            == LocalFloorPlanFileBuilder.sha256(expectedUpload.files.navigationMapJSON))

        store.registerFloorPlan()
        precondition(store.isUploadingFloorPlan && !store.canGoBack)
        store.goBack()
        precondition(store.phase == .floorPlanCreation && draft.step == .scaling,
                     "back must not discard a running upload")
        try await wait { !store.isUploadingFloorPlan }
        precondition(store.phase == .floorPlanCreation && store.floorPlans.isEmpty)
        precondition(store.floorPlanUploadError != nil && draft.canRegister)

        store.retryFloorPlanUpload()
        try await wait { store.phase == .floorPlanList }
        let uploads = await repository.uploads()
        precondition(uploads.count == 2)
        precondition(uploads[0].0 == uploads[1].0)
        let uploadedReference = uploads[1].0
        let uploadedFiles = uploads[1].1
        let uploadedManifest = try JSONDecoder().decode(
            FloorPlanManifest.self,
            from: uploadedFiles.navigationMapJSON
        )
        precondition(uploadedFiles.imagePNG == expectedUpload.files.imagePNG)
        precondition(uploadedFiles.resolvedMask == expectedUpload.files.resolvedMask)
        precondition(uploadedReference.floorPlanID == uploadedManifest.floorPlanID)
        precondition(uploadedReference.navigationSHA256
            == LocalFloorPlanFileBuilder.sha256(uploadedFiles.navigationMapJSON))
        precondition(store.selectedFloorPlan?.reference == uploadedReference)
        precondition(store.selectedFloorPlan?.registeredPlan?.id == uploadedReference.floorPlanID)
        precondition(draft.step == .information && draft.image == nil)

        store.openSessionCreation()
        precondition(store.canCreateSession)
        store.createSession()
        try await wait { store.phase == .teamReadiness }
        precondition(store.currentSession?.floorPlan == uploadedReference)
        store.goBack()
        try await wait { store.phase == .sessionCreation }

        store.openFloorPlanCreation()
        _ = try await prepareDraft(draft, importer: importer)
        catalog.saveError = URLError(.cannotWriteToFile)
        store.registerFloorPlan()
        try await wait { !store.isUploadingFloorPlan }
        precondition(store.floorPlans.count == 1, "로컬 저장 실패는 도면을 목록에 추가하지 않아야 한다")
        precondition(store.floorPlanUploadError?.contains("기기에 목록") == true)
        catalog.saveError = nil
        store.retryFloorPlanUpload()
        try await wait { store.phase == .floorPlanList }
        let localRetryUploads = await repository.uploads()
        precondition(localRetryUploads.count == 4)
        precondition(localRetryUploads[2].0 == localRetryUploads[3].0,
                     "로컬 저장 재시도는 동일한 Storage 참조를 사용해야 한다")
        precondition(store.floorPlans.count == 2)

        await repository.failNextUpload()
        store.openFloorPlanCreation()
        _ = try await prepareDraft(draft, importer: importer)
        store.registerFloorPlan()
        try await wait { !store.isUploadingFloorPlan }
        precondition(store.floorPlanUploadError != nil && store.canGoBack)
        store.goBack()
        precondition(store.phase == .floorPlanCreation && draft.step == .editing && draft.image != nil,
                     "first back preserves the draft for editing")
        precondition(store.floorPlanUploadError == nil && !store.isUploadingFloorPlan)
        store.retryFloorPlanUpload()
        precondition(!store.isUploadingFloorPlan, "back must discard the failed upload snapshot")
        store.goBack()
        precondition(store.phase == .floorPlanList && draft.image == nil && draft.name.isEmpty)
        precondition(store.floorPlans.count == 2, "a failed upload must not add a plan")
        store.openFloorPlanCreation()
        precondition(store.floorPlanUploadError == nil && draft.step == .information)
        store.retryFloorPlanUpload()
        precondition(!store.isUploadingFloorPlan, "reopening must not retry the previous registration")
        let finalUploads = await repository.uploads()
        precondition(finalUploads.count == 5)

        try await checkOddImageUpload()
        print("PASS: FloorPlanFiles 생성, 홀수 이미지 계약, SHA-256 참조, 업로드·로컬 저장 실패 재시도, 세션 참조")
    }

    private static func checkImportLifecycle() async throws {
        let importer = ControlledImporter()
        let draft = FloorPlanDraftStore(importer: importer)

        draft.importImage(from: URL(fileURLWithPath: "/virtual/cancelled.png"))
        precondition(draft.processingStage == .analyzingImage)
        precondition(draft.isProcessing && draft.isImporting)
        try await wait { await importer.has("cancelled.png") }
        draft.cancelProcessing()
        precondition(draft.processingStage == .idle && !draft.isProcessing)
        precondition(draft.errorMessage == nil, "사용자 취소는 오류로 표시하지 않아야 한다")
        await importer.succeed("cancelled.png")
        try await Task.sleep(for: .milliseconds(20))
        precondition(draft.image == nil, "취소된 작업의 늦은 결과를 반영하지 않아야 한다")

        draft.importImage(from: URL(fileURLWithPath: "/virtual/original.png"))
        try await wait { await importer.has("original.png") }
        await importer.succeed("original.png", suggestedOutline: outline)
        try await wait { !draft.isProcessing }
        precondition(draft.image?.fileName == "original.png")
        precondition(draft.outline == outline, "자동 제안 영역을 첫 미리보기에 적용해야 한다")
        draft.setEditorMode(.brush)
        let pendingStroke = LocalEditStroke(mode: .block,
            points: [LocalPlanPoint(x: 0.2, y: 0.2), LocalPlanPoint(x: 0.4, y: 0.4)],
            normalizedDiameter: 0.02)
        draft.stageBrushStroke(pendingStroke)

        draft.importImage(from: URL(fileURLWithPath: "/virtual/failure.png"))
        try await wait { await importer.has("failure.png") }
        await importer.fail("failure.png", error: LocalFloorPlanError.invalid("분석 실패"))
        try await wait { !draft.isProcessing }
        precondition(draft.errorMessage == "분석 실패")
        precondition(draft.image?.fileName == "original.png")
        precondition(draft.pendingBrushStrokes == [pendingStroke], "교체 실패 시 기존 편집 작업본을 유지해야 한다")

        draft.importImage(from: URL(fileURLWithPath: "/virtual/stale.png"))
        try await wait { await importer.has("stale.png") }
        draft.importImage(from: URL(fileURLWithPath: "/virtual/latest.png"))
        try await wait { await importer.has("latest.png") }
        await importer.succeed("stale.png")
        try await Task.sleep(for: .milliseconds(20))
        precondition(draft.image?.fileName == "original.png", "이전 요청의 결과를 반영하지 않아야 한다")
        await importer.succeed("latest.png")
        try await wait { !draft.isProcessing }
        precondition(draft.image?.fileName == "latest.png")
        precondition(draft.pendingBrushStrokes.isEmpty, "성공한 교체만 새 작업본을 적용해야 한다")

        let pickerCancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        draft.reportImportFailure(pickerCancellation)
        precondition(draft.errorMessage == nil, "파일 선택 취소는 오류로 표시하지 않아야 한다")
    }

    private static func prepareDraft(_ draft: FloorPlanDraftStore, importer: ControlledImporter) async throws -> LocalEditStroke {
        draft.setName("  새 도면  ")
        draft.importImage(from: URL(fileURLWithPath: "/virtual/original.png"))
        try await wait { await importer.has("original.png") }
        await importer.succeed("original.png")
        try await wait { !draft.isProcessing }
        for point in outline { draft.placePoint(point) }
        draft.confirmOutline()
        try await wait { !draft.isProcessing }
        let stroke = LocalEditStroke(
            mode: .block,
            points: [LocalPlanPoint(x: 0.3, y: 0.3), LocalPlanPoint(x: 0.6, y: 0.3)],
            normalizedDiameter: 0.03
        )
        draft.setEditorMode(.brush)
        draft.stageBrushStroke(stroke)
        draft.applyPendingBrush(.block)
        try await wait { !draft.isProcessing }
        draft.continueToScale()
        draft.placePoint(LocalPlanPoint(x: 0.2, y: 0.2))
        draft.placePoint(LocalPlanPoint(x: 0.8, y: 0.2))
        draft.setDistance("10")
        precondition(draft.canRegister)
        return stroke
    }

    private static let outline = [
        LocalPlanPoint(x: 0.1, y: 0.1),
        LocalPlanPoint(x: 0.9, y: 0.1),
        LocalPlanPoint(x: 0.9, y: 0.9),
        LocalPlanPoint(x: 0.1, y: 0.9)
    ]

    private static func checkOddImageUpload() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("odd-floorplan-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = CGContext(data: nil, width: 101, height: 81, bitsPerComponent: 8,
            bytesPerRow: 101 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 101, height: 81))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))

        let imported = try await LocalFloorPlanImportService().process(url: url)
        let image = imported.image
        let resolved = try LocalFloorPlanGeometry.resolve(base: imported.baseGrid,
            width: image.width, height: image.height, edits: [], outline: outline)
        let scale = LocalPlanScale(a: .init(x: 0.2, y: 0.2), b: .init(x: 0.8, y: 0.2), meters: 10)
        let registration = LocalRegisteredFloorPlan(id: UUID(), name: "홀수 도면", image: image,
            baseGrid: imported.baseGrid, edits: [], outline: outline, scale: scale, resolvedGrid: resolved)
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let manifest = try JSONDecoder().decode(FloorPlanManifest.self, from: upload.files.navigationMapJSON)
        let grid = manifest.navigationGrid
        let png = CGImageSourceCreateWithData(upload.files.imagePNG as CFData, nil)!
        let output = CGImageSourceCreateImageAtIndex(png, 0, nil)!
        precondition(output.width == 102 && output.height == 82)
        precondition(manifest.imageWidth == output.width && manifest.imageHeight == output.height)
        precondition(manifest.imageWidth == grid.columns * grid.cellSizePixels)
        precondition(manifest.imageHeight == grid.rows * grid.cellSizePixels)
        precondition(upload.files.resolvedMask.count == grid.columns * grid.rows)
        precondition(manifest.scale.a.x == scale.a.x * Double(output.width))
        precondition(manifest.scale.b.y == scale.b.y * Double(output.height))
        precondition(manifest.imageSHA256 == LocalFloorPlanFileBuilder.sha256(upload.files.imagePNG))
        precondition(grid.maskSHA256 == LocalFloorPlanFileBuilder.sha256(upload.files.resolvedMask))
        precondition(upload.reference.navigationSHA256 == LocalFloorPlanFileBuilder.sha256(upload.files.navigationMapJSON))

        var unalignedImage = image
        unalignedImage.width = 101
        unalignedImage.height = 81
        let unaligned = LocalRegisteredFloorPlan(id: registration.id, name: registration.name,
            image: unalignedImage, baseGrid: imported.baseGrid, edits: [], outline: outline,
            scale: scale, resolvedGrid: resolved)
        do {
            _ = try LocalFloorPlanFileBuilder.build(from: unaligned)
            fatalError("an unaligned image must be rejected before upload")
        } catch is LocalFloorPlanError {}
    }

    private static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                throw LocalFloorPlanError.invalid("Test timed out")
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw LocalFloorPlanError.invalid(message) }
        return value
    }
}
