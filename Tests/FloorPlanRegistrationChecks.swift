import CQBCore
import Foundation

private actor ControlledImporter: FloorPlanImporting {
    private var pending: [String: CheckedContinuation<LocalExtractionResult, Error>] = [:]

    func process(url: URL) async throws -> LocalExtractionResult {
        try await withCheckedThrowingContinuation { pending[url.lastPathComponent] = $0 }
    }

    func has(_ name: String) -> Bool { pending[name] != nil }

    func succeed(_ name: String) {
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
            )
        ))
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
}

@main
@MainActor
enum FloorPlanRegistrationChecks {
    static func main() async throws {
        let importer = ControlledImporter()
        let draft = FloorPlanDraftStore(importer: importer)
        let repository = ControlledFloorPlanFileRepository(failures: 1)
        let store = InstructorStore(
            floorPlans: [],
            floorPlanDraft: draft,
            floorPlanFileRepository: repository
        )

        store.openFloorPlanCreation()
        draft.setName("  새 도면  ")
        draft.importImage(from: URL(fileURLWithPath: "/virtual/original.png"))
        try await wait { await importer.has("original.png") }
        await importer.succeed("original.png")
        try await wait { !draft.isProcessing }

        for point in [
            LocalPlanPoint(x: 0.1, y: 0.1),
            LocalPlanPoint(x: 0.9, y: 0.1),
            LocalPlanPoint(x: 0.9, y: 0.9),
            LocalPlanPoint(x: 0.1, y: 0.9)
        ] {
            draft.placePoint(point)
        }
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
        precondition(store.currentSession?.floorPlan == uploadedReference)

        print("PASS: FloorPlanFiles 생성, SHA-256 참조, 업로드 실패 재시도, 세션 참조")
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
