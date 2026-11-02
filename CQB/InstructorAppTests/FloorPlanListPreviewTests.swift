import CQBCore
import ImageIO
import UIKit
import XCTest
@testable import InstructorApp

@MainActor
final class FloorPlanListPreviewTests: XCTestCase {
    func testOpeningListSelectsAndLoadsFirstPreview() async throws {
        let first = makePlan(id: "first")
        let second = makePlan(id: "second")
        let loader = PreviewLoaderStub()
        let store = InstructorStore(
            floorPlans: [first, second],
            floorPlanListPreviewLoader: loader
        )

        store.openFloorPlanList()

        XCTAssertEqual(store.previewedFloorPlanID, first.id)
        XCTAssertEqual(store.floorPlanListPreviewState, .loading)
        let didLoad = await waitUntil { store.floorPlanListPreviewState == .loaded }
        XCTAssertTrue(didLoad)
        let callCount = await loader.callCount(for: first.id)
        XCTAssertEqual(callCount, 1)
    }

    func testPreviewDetailCannotOpenUntilPreviewFinishesLoading() async throws {
        let plan = makePlan(id: "plan")
        let loader = PreviewLoaderStub(delays: [plan.id: .milliseconds(120)])
        let store = InstructorStore(
            floorPlans: [plan],
            floorPlanListPreviewLoader: loader
        )

        store.openFloorPlanList()

        XCTAssertEqual(store.floorPlanListPreviewState, .loading)
        XCTAssertFalse(store.canOpenPreviewedFloorPlanDetail)
        store.openPreviewedFloorPlanDetail()
        XCTAssertEqual(store.phase, .floorPlanList)

        let didLoad = await waitUntil { store.floorPlanListPreviewState == .loaded }
        XCTAssertTrue(didLoad)
        XCTAssertTrue(store.canOpenPreviewedFloorPlanDetail)

        store.openPreviewedFloorPlanDetail()

        XCTAssertEqual(store.phase, .floorPlanDetail)
        XCTAssertEqual(store.viewedFloorPlanID, plan.id)
    }

    func testDeletingPlanSelectsAdjacentPreview() async throws {
        let first = makePlan(id: "first")
        let second = makePlan(id: "second")
        let third = makePlan(id: "third")
        let catalog = DemoFloorPlanCatalogRepository(floorPlans: [first, second, third])
        let loader = PreviewLoaderStub()
        let store = InstructorStore(
            floorPlans: [first, second, third],
            floorPlanListPreviewLoader: loader,
            floorPlanCatalogRepository: catalog
        )
        store.openFloorPlanList()
        store.openFloorPlanDetail(second.id)

        store.deleteViewedFloorPlan()

        XCTAssertEqual(store.phase, .floorPlanList)
        XCTAssertEqual(store.floorPlans.map(\.id), [first.id, third.id])
        XCTAssertEqual(store.previewedFloorPlanID, third.id)
        let didLoad = await waitUntil { store.floorPlanListPreviewState == .loaded }
        XCTAssertTrue(didLoad)
    }

    func testSelectingFloorPlanLoadsPreviewAndKeepsSessionSelectionIndependent() async throws {
        let first = makePlan(id: "first")
        let second = makePlan(id: "second")
        let loader = PreviewLoaderStub()
        let store = InstructorStore(
            floorPlans: [first, second],
            floorPlanListPreviewLoader: loader
        )
        store.openFloorPlanList()

        store.selectFloorPlanPreview(second.id)

        XCTAssertEqual(store.floorPlanListPreviewState, .loading)
        XCTAssertEqual(store.previewedFloorPlanID, second.id)
        XCTAssertEqual(store.selectedFloorPlanID, first.id)
        let didLoad = await waitUntil { store.floorPlanListPreviewState == .loaded }
        XCTAssertTrue(didLoad)
        XCTAssertNotNil(store.floorPlanListPreviewImage)
    }

    func testRapidSelectionOnlyAppliesLatestPreview() async throws {
        let first = makePlan(id: "first")
        let second = makePlan(id: "second")
        let loader = PreviewLoaderStub(delays: [first.id: .milliseconds(120)])
        let store = InstructorStore(
            floorPlans: [first, second],
            floorPlanListPreviewLoader: loader
        )
        store.openFloorPlanList()

        store.selectFloorPlanPreview(first.id)
        store.selectFloorPlanPreview(second.id)

        let didLoad = await waitUntil { store.floorPlanListPreviewState == .loaded }
        XCTAssertTrue(didLoad)
        XCTAssertEqual(store.previewedFloorPlanID, second.id)
        try? await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(store.previewedFloorPlanID, second.id)
        XCTAssertEqual(store.floorPlanListPreviewState, .loaded)
    }

    func testReselectingLoadedFloorPlanDoesNotRequestPreviewAgain() async throws {
        let plan = makePlan(id: "plan")
        let loader = PreviewLoaderStub()
        let store = InstructorStore(
            floorPlans: [plan],
            floorPlanListPreviewLoader: loader
        )
        store.openFloorPlanList()

        store.selectFloorPlanPreview(plan.id)
        let didLoad = await waitUntil { store.floorPlanListPreviewState == .loaded }
        XCTAssertTrue(didLoad)
        store.selectFloorPlanPreview(plan.id)

        let callCount = await loader.callCount(for: plan.id)
        XCTAssertEqual(callCount, 1)
    }

    func testFailedPreviewCanRetry() async throws {
        let plan = makePlan(id: "plan")
        let loader = PreviewLoaderStub(failuresRemaining: [plan.id: 1])
        let store = InstructorStore(
            floorPlans: [plan],
            floorPlanListPreviewLoader: loader
        )
        store.openFloorPlanList()

        store.selectFloorPlanPreview(plan.id)
        let didFail = await waitUntil {
            if case .failed = store.floorPlanListPreviewState { return true }
            return false
        }
        XCTAssertTrue(didFail)
        XCTAssertFalse(store.canOpenPreviewedFloorPlanDetail)
        store.openPreviewedFloorPlanDetail()
        XCTAssertEqual(store.phase, .floorPlanList)

        store.retryFloorPlanListPreview()

        let didLoad = await waitUntil { store.floorPlanListPreviewState == .loaded }
        XCTAssertTrue(didLoad)
        XCTAssertTrue(store.canOpenPreviewedFloorPlanDetail)
        let callCount = await loader.callCount(for: plan.id)
        XCTAssertEqual(callCount, 2)
    }

    func testPreviewLoaderReusesReference() async throws {
        let registration = try makeRegistration(width: 64, height: 32)
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let remote = PreviewRemoteStub(result: .success(upload.files))
        let loader = LocalFloorPlanListPreviewLoader(repository: remote, maximumPixelSize: 320)
        let plan = makePlan(id: "remote", reference: upload.reference)

        _ = try await loader.load(plan)
        _ = try await loader.load(plan)

        let downloadCount = await remote.count()
        XCTAssertEqual(downloadCount, 1, "같은 reference가 원격에서 \(downloadCount)회 다운로드됐습니다.")
    }

    func testConcurrentPreviewRequestsShareOneDownload() async throws {
        let registration = try makeRegistration(width: 64, height: 32)
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let remote = PreviewRemoteStub(
            result: .success(upload.files),
            delay: .milliseconds(50)
        )
        let loader = LocalFloorPlanListPreviewLoader(repository: remote)
        let plan = makePlan(id: "concurrent", reference: upload.reference)

        async let first = loader.load(plan)
        async let second = loader.load(plan)
        _ = try await (first, second)

        let downloadCount = await remote.count()
        XCTAssertEqual(downloadCount, 1)
    }

    func testCancelingAllWaitersCancelsSharedWorkAndAllowsRetry() async throws {
        let registration = try makeRegistration(width: 64, height: 32)
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let remote = ControllablePreviewRemoteStub(files: upload.files)
        let loader = LocalFloorPlanListPreviewLoader(repository: remote)
        let plan = makePlan(id: "cancelled", reference: upload.reference)

        let first = Task { try await loader.load(plan) }
        let second = Task { try await loader.load(plan) }
        let didStart = await waitUntilAsync { await remote.downloadCount == 1 }
        XCTAssertTrue(didStart)

        first.cancel()
        try? await Task.sleep(for: .milliseconds(30))
        let cancellationCountWithWaiter = await remote.cancellationCount
        XCTAssertEqual(cancellationCountWithWaiter, 0, "남은 waiter가 있으면 공유 작업을 유지해야 합니다.")

        second.cancel()
        let didCancel = await waitUntilAsync { await remote.cancellationCount == 1 }
        XCTAssertTrue(didCancel)
        await assertCancellation(of: first)
        await assertCancellation(of: second)

        await remote.allowCompletion()
        _ = try await loader.load(plan)
        let retryDownloadCount = await remote.downloadCount
        XCTAssertEqual(retryDownloadCount, 2, "취소된 in-flight 요청은 재시도를 막지 않아야 합니다.")
    }

    func testPreviewMemoryCacheEvictsLeastRecentlyUsedEntry() async throws {
        let registrations = try [
            makeRegistration(width: 64, height: 32),
            makeRegistration(width: 80, height: 48),
            makeRegistration(width: 96, height: 64)
        ]
        let uploads = try registrations.map { try LocalFloorPlanFileBuilder.build(from: $0) }
        let previews = try registrations.map {
            try LocalFloorPlanListPreviewRenderer.render(
                imagePNG: $0.image.pngData,
                maximumPixelSize: 320
            )
        }
        let sizes = previews.map(\.imagePNGData.count)
        let twoEntryLimit = [
            sizes[0] + sizes[1],
            sizes[0] + sizes[2],
            sizes[1] + sizes[2]
        ].max()!
        let remote = PreviewRemoteMapStub(uploads: uploads)
        let loader = LocalFloorPlanListPreviewLoader(
            repository: remote,
            maximumPixelSize: 320,
            memoryLimitBytes: twoEntryLimit
        )
        let plans = uploads.enumerated().map { index, upload in
            makePlan(id: "lru-\(index)", reference: upload.reference)
        }

        _ = try await loader.load(plans[0])
        _ = try await loader.load(plans[1])
        _ = try await loader.load(plans[0])
        _ = try await loader.load(plans[2])
        _ = try await loader.load(plans[0])
        _ = try await loader.load(plans[1])

        let firstCount = await remote.count(for: uploads[0].reference)
        let secondCount = await remote.count(for: uploads[1].reference)
        let thirdCount = await remote.count(for: uploads[2].reference)
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 2)
        XCTAssertEqual(thirdCount, 1)
    }

    func testPreviewLargerThanMemoryLimitIsNotRetained() async throws {
        let registration = try makeRegistration(width: 64, height: 32)
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let preview = try LocalFloorPlanListPreviewRenderer.render(
            imagePNG: registration.image.pngData,
            maximumPixelSize: 320
        )
        let byteCount = preview.imagePNGData.count
        let remote = PreviewRemoteMapStub(uploads: [upload])
        let loader = LocalFloorPlanListPreviewLoader(
            repository: remote,
            maximumPixelSize: 320,
            memoryLimitBytes: max(0, byteCount - 1)
        )
        let plan = makePlan(id: "oversized", reference: upload.reference)

        _ = try await loader.load(plan)
        _ = try await loader.load(plan)

        let downloadCount = await remote.count(for: upload.reference)
        XCTAssertEqual(downloadCount, 2)
    }

    func testPreviewRendererDownsamplesImage() throws {
        let registration = try makeRegistration(width: 2_000, height: 1_000)
        let preview = try LocalFloorPlanListPreviewRenderer.render(
            imagePNG: registration.image.pngData,
            maximumPixelSize: 320
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(preview.imagePNGData as CFData, nil))
        let thumbnail = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(
            thumbnail.width,
            320,
            "썸네일 너비가 \(thumbnail.width)x\(thumbnail.height)로 생성됐습니다."
        )
        XCTAssertLessThanOrEqual(
            thumbnail.height,
            320,
            "썸네일 높이가 \(thumbnail.width)x\(thumbnail.height)로 생성됐습니다."
        )
    }

    func testCachedFilesProvidePreviewOfflineAfterRelaunch() async throws {
        let registration = try makeRegistration(width: 64, height: 32)
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let plan = makePlan(id: "cached", reference: upload.reference)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloorPlanListPreviewTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let online = PreviewRemoteStub(result: .success(upload.files))
        let onlineCache = makeFileCache(remote: online, directory: directory)
        _ = try await LocalFloorPlanListPreviewLoader(repository: onlineCache).load(plan)
        let onlineDownloadCount = await online.count()
        XCTAssertEqual(onlineDownloadCount, 1)

        let offline = PreviewRemoteStub(result: .failure(PreviewTestError.offline))
        let offlineCache = makeFileCache(remote: offline, directory: directory)
        let restored = try await LocalFloorPlanListPreviewLoader(repository: offlineCache).load(plan)

        XCTAssertFalse(restored.imagePNGData.isEmpty)
        let offlineDownloadCount = await offline.count()
        XCTAssertEqual(offlineDownloadCount, 0)
    }

    private func makeFileCache(
        remote: PreviewRemoteStub,
        directory: URL
    ) -> CachedFloorPlanFileRepository {
        CachedFloorPlanFileRepository(
            remote: remote,
            configuration: .init(
                directory: directory,
                diskLimitBytes: 10 * 1_024 * 1_024,
                memoryLimitBytes: 10 * 1_024 * 1_024
            )
        )
    }

    private func makePlan(
        id: String,
        reference: FloorPlanReference? = nil
    ) -> InstructorFloorPlan {
        InstructorFloorPlan(
            id: id,
            name: "도면 \(id)",
            fileName: "\(id).png",
            referenceDistance: 10,
            reference: reference ?? FloorPlanReference(
                floorPlanID: UUID(),
                navigationSHA256: "reference-\(id)"
            ),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func makeRegistration(width: Int, height: Int) throws -> LocalRegisteredFloorPlan {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let cellSize = 16
        let columns = (width + cellSize - 1) / cellSize
        let rows = (height + cellSize - 1) / cellSize
        let grid = LocalObstacleGrid(
            columns: columns,
            rows: rows,
            cellSizePixels: cellSize,
            blocked: [UInt8](repeating: 0, count: columns * rows)
        )
        return LocalRegisteredFloorPlan(
            id: UUID(),
            name: "테스트 도면",
            image: LocalImportedImage(
                pngData: try XCTUnwrap(image.pngData()),
                width: width,
                height: height,
                fileName: "plan.png"
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
                meters: 10
            ),
            resolvedGrid: grid,
            extractionAlgorithm: .v13
        )
    }

    private func waitUntil(
        attempts: Int = 200,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func waitUntilAsync(
        attempts: Int = 200,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    private func assertCancellation(
        of task: Task<FloorPlanListPreviewSnapshot, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("취소된 waiter는 성공하면 안 됩니다.", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, file: file, line: line)
        }
    }
}

private actor PreviewLoaderStub: FloorPlanListPreviewLoading {
    private let delays: [String: Duration]
    private var failuresRemaining: [String: Int]
    private var callCounts: [String: Int] = [:]

    init(
        delays: [String: Duration] = [:],
        failuresRemaining: [String: Int] = [:]
    ) {
        self.delays = delays
        self.failuresRemaining = failuresRemaining
    }

    func load(_ floorPlan: InstructorFloorPlan) async throws -> FloorPlanListPreviewSnapshot {
        callCounts[floorPlan.id, default: 0] += 1
        if let delay = delays[floorPlan.id] {
            do {
                try await Task.sleep(for: delay)
            } catch {
                // 취소된 이전 작업도 완료시켜 Store의 오래된 결과 방어를 검증한다.
            }
        }
        if failuresRemaining[floorPlan.id, default: 0] > 0 {
            failuresRemaining[floorPlan.id, default: 0] -= 1
            throw PreviewTestError.offline
        }
        let data = Self.pngData()
        return FloorPlanListPreviewSnapshot(imagePNGData: data)
    }

    func callCount(for id: String) -> Int {
        callCounts[id, default: 0]
    }

    private nonisolated static func pngData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format)
            .image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
            .pngData()!
    }
}

private actor PreviewRemoteStub: FloorPlanFileRepository {
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

    func count() -> Int {
        downloadCount
    }
}

private actor ControllablePreviewRemoteStub: FloorPlanFileRepository {
    private let files: FloorPlanFiles
    private var canComplete = false
    private(set) var downloadCount = 0
    private(set) var cancellationCount = 0

    init(files: FloorPlanFiles) {
        self.files = files
    }

    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        downloadCount += 1
        do {
            while !canComplete {
                try await Task.sleep(for: .milliseconds(10))
            }
            return files
        } catch {
            if error is CancellationError { cancellationCount += 1 }
            throw error
        }
    }

    func allowCompletion() {
        canComplete = true
    }
}

private actor PreviewRemoteMapStub: FloorPlanFileRepository {
    private let filesByReference: [FloorPlanReference: FloorPlanFiles]
    private var downloadCounts: [FloorPlanReference: Int] = [:]

    init(uploads: [LocalFloorPlanUpload]) {
        filesByReference = Dictionary(uniqueKeysWithValues: uploads.map { ($0.reference, $0.files) })
    }

    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        downloadCounts[reference, default: 0] += 1
        guard let files = filesByReference[reference] else { throw RepositoryError.notFound }
        return files
    }

    func count(for reference: FloorPlanReference) -> Int {
        downloadCounts[reference, default: 0]
    }
}

private enum PreviewTestError: Error {
    case offline
}
