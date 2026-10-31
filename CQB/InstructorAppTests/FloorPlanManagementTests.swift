import CQBCore
import UIKit
import XCTest
@testable import InstructorApp

@MainActor
final class FloorPlanManagementTests: XCTestCase {
    func testStorageFilesRestoreEditableMaskSnapshot() throws {
        let registration = try makeRegistration()
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let catalog = makePlan(registration: registration, reference: upload.reference)

        let snapshot = try LocalFloorPlanFileLoader.load(
            files: upload.files,
            reference: upload.reference,
            catalog: catalog
        )

        XCTAssertEqual(snapshot.registration.name, catalog.name)
        XCTAssertEqual(snapshot.registration.image.fileName, catalog.fileName)
        XCTAssertEqual(snapshot.registration.baseGrid, registration.resolvedGrid)
        XCTAssertEqual(snapshot.registration.resolvedGrid, registration.resolvedGrid)
        XCTAssertEqual(snapshot.registration.scale, registration.scale)
        XCTAssertFalse(snapshot.maskPNGData.isEmpty)
    }

    func testStorageFilesRejectTamperedMask() throws {
        let registration = try makeRegistration()
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let catalog = makePlan(registration: registration, reference: upload.reference)
        let tampered = FloorPlanFiles(
            imagePNG: upload.files.imagePNG,
            navigationMapJSON: upload.files.navigationMapJSON,
            resolvedMask: Data([0, 0, 0, 0])
        )

        XCTAssertThrowsError(try LocalFloorPlanFileLoader.load(
            files: tampered,
            reference: upload.reference,
            catalog: catalog
        )) { error in
            XCTAssertEqual(error as? RepositoryError, .integrityMismatch)
        }
    }

    func testMaskEditReplacesReferenceWithoutDuplicatingCatalogEntry() async throws {
        let registration = try makeRegistration()
        let originalReference = FloorPlanReference(
            floorPlanID: registration.id,
            navigationSHA256: "original-reference"
        )
        let plan = makePlan(registration: registration, reference: originalReference)
        let catalog = DemoFloorPlanCatalogRepository(floorPlans: [plan])
        let recorder = FloorPlanUploadRecorder()
        let store = InstructorStore(
            floorPlans: [plan],
            floorPlanFileRepository: RecordingFloorPlanFileRepository(recorder: recorder),
            floorPlanCatalogRepository: catalog
        )

        store.openFloorPlanList()
        store.openFloorPlanDetail(plan.id)
        let didLoadDetail = await waitUntil { store.floorPlanDetailState == .loaded }
        XCTAssertTrue(didLoadDetail)

        store.beginFloorPlanMaskEditing()
        XCTAssertEqual(store.phase, .floorPlanEditing)
        store.saveFloorPlanMaskEdit()

        let didSaveEdit = await waitUntil {
            store.phase == .floorPlanDetail && !store.isUploadingFloorPlan
        }
        XCTAssertTrue(didSaveEdit)
        XCTAssertEqual(store.floorPlans.count, 1)
        XCTAssertEqual(store.floorPlans.first?.id, plan.id)
        XCTAssertNotEqual(store.floorPlans.first?.reference.floorPlanID, originalReference.floorPlanID)
        XCTAssertEqual(try catalog.fetchAll().map(\.id), [plan.id])
        let uploadCount = await recorder.uploadCount
        XCTAssertEqual(uploadCount, 1)
    }

    func testDeleteRemovesLocalCatalogEntryButDoesNotRequestStorageDeletion() throws {
        let registration = try makeRegistration()
        let plan = makePlan(
            registration: registration,
            reference: FloorPlanReference(
                floorPlanID: registration.id,
                navigationSHA256: "existing-reference"
            )
        )
        let catalog = DemoFloorPlanCatalogRepository(floorPlans: [plan])
        let store = InstructorStore(
            floorPlans: [plan],
            floorPlanCatalogRepository: catalog
        )

        store.openFloorPlanList()
        store.openFloorPlanDetail(plan.id)
        store.deleteViewedFloorPlan()

        XCTAssertEqual(store.phase, .floorPlanList)
        XCTAssertTrue(store.floorPlans.isEmpty)
        XCTAssertTrue(try catalog.fetchAll().isEmpty)
    }

    func testDeleteFailureKeepsDetailAndCatalogEntry() throws {
        let registration = try makeRegistration()
        let plan = makePlan(
            registration: registration,
            reference: FloorPlanReference(
                floorPlanID: registration.id,
                navigationSHA256: "existing-reference"
            )
        )
        let catalog = DemoFloorPlanCatalogRepository(floorPlans: [plan])
        catalog.deleteError = CocoaError(.fileWriteUnknown)
        let store = InstructorStore(
            floorPlans: [plan],
            floorPlanCatalogRepository: catalog
        )

        store.openFloorPlanList()
        store.openFloorPlanDetail(plan.id)
        store.deleteViewedFloorPlan()

        XCTAssertEqual(store.phase, .floorPlanDetail)
        XCTAssertEqual(store.floorPlans, [plan])
        XCTAssertNotNil(store.floorPlanDeletionError)
        XCTAssertEqual(try catalog.fetchAll(), [plan])
    }

    private func makeRegistration() throws -> LocalRegisteredFloorPlan {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
            .image { context in
                UIColor.white.setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
                UIColor.black.setStroke()
                context.cgContext.stroke(CGRect(x: 2, y: 2, width: 12, height: 12))
            }
        let grid = LocalObstacleGrid(
            columns: 2,
            rows: 2,
            cellSizePixels: 8,
            blocked: [1, 0, 0, 1]
        )
        return LocalRegisteredFloorPlan(
            id: UUID(),
            name: "테스트 도면",
            image: LocalImportedImage(
                pngData: try XCTUnwrap(image.pngData()),
                width: 16,
                height: 16,
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
                meters: 4
            ),
            resolvedGrid: grid,
            extractionAlgorithm: .v13
        )
    }

    private func makePlan(
        registration: LocalRegisteredFloorPlan,
        reference: FloorPlanReference
    ) -> InstructorFloorPlan {
        InstructorFloorPlan(
            id: "catalog-plan",
            name: registration.name,
            fileName: registration.image.fileName,
            referenceDistance: registration.scale.meters,
            reference: reference,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            registeredPlan: registration
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
}

private actor FloorPlanUploadRecorder {
    private(set) var uploadCount = 0

    func recordUpload() {
        uploadCount += 1
    }
}

private struct RecordingFloorPlanFileRepository: FloorPlanFileRepository {
    let recorder: FloorPlanUploadRecorder

    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {
        await recorder.recordUpload()
    }

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        throw RepositoryError.notFound
    }
}
