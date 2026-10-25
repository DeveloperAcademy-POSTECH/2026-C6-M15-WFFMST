import CQBCore
import SwiftData
import XCTest
@testable import InstructorApp

@MainActor
final class FloorPlanCatalogRepositoryTests: XCTestCase {
    func testSavedFloorPlanCanBeRestoredFromANewRepository() throws {
        let container = try makeContainer()
        let firstRepository = SwiftDataFloorPlanCatalogRepository(container: container)
        let floorPlan = makeFloorPlan()

        try firstRepository.save(floorPlan)

        let restored = try SwiftDataFloorPlanCatalogRepository(container: container).fetchAll()
        XCTAssertEqual(restored, [floorPlan])
    }

    func testSavingSameCatalogIDUpdatesWithoutDuplicating() throws {
        let container = try makeContainer()
        let repository = SwiftDataFloorPlanCatalogRepository(container: container)
        let original = makeFloorPlan()
        let replacement = InstructorFloorPlan(
            id: original.id,
            name: "수정된 도면",
            fileName: "updated.png",
            referenceDistance: 20,
            reference: FloorPlanReference(
                floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000902")!,
                navigationSHA256: "updated-hash"
            ),
            createdAt: original.createdAt,
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try repository.save(original)
        try repository.save(replacement)

        XCTAssertEqual(try repository.fetchAll(), [replacement])
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: StoredFloorPlan.self, configurations: configuration)
    }

    private func makeFloorPlan() -> InstructorFloorPlan {
        InstructorFloorPlan(
            id: "catalog-plan",
            name: "테스트 도면",
            fileName: "plan.png",
            referenceDistance: 10,
            reference: FloorPlanReference(
                floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
                navigationSHA256: "original-hash"
            ),
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }
}
