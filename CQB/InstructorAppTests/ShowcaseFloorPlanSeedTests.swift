import CQBCore
import XCTest
@testable import InstructorApp

@MainActor
final class ShowcaseFloorPlanSeedTests: XCTestCase {
    func testPrepareCatalogAddsCompletedFloorPlanToEmptyCatalog() throws {
        let repository = DemoFloorPlanCatalogRepository()

        try ShowcaseFloorPlanSeed.prepareCatalog(in: repository)

        XCTAssertEqual(try repository.fetchAll(), [ShowcaseFloorPlanSeed.c5])
        XCTAssertEqual(ShowcaseFloorPlanSeed.c5.worldMap?.floorPlan, ShowcaseFloorPlanSeed.c5.reference)
    }

    func testPrepareCatalogDoesNotDuplicateExistingSeed() throws {
        let repository = DemoFloorPlanCatalogRepository()

        try ShowcaseFloorPlanSeed.prepareCatalog(in: repository)
        try ShowcaseFloorPlanSeed.prepareCatalog(in: repository)

        XCTAssertEqual(try repository.fetchAll(), [ShowcaseFloorPlanSeed.c5])
    }

    func testPrepareCatalogRemovesOtherFloorPlans() throws {
        let existing = InstructorFloorPlan(
            id: "existing-plan",
            name: "기존 도면",
            fileName: "existing.png",
            referenceDistance: 10
        )
        let repository = DemoFloorPlanCatalogRepository(floorPlans: [existing])

        try ShowcaseFloorPlanSeed.prepareCatalog(in: repository)

        XCTAssertEqual(try repository.fetchAll(), [ShowcaseFloorPlanSeed.c5])
    }

    func testPrepareCatalogRestoresChangedSeedMetadata() throws {
        let incomplete = InstructorFloorPlan(
            id: ShowcaseFloorPlanSeed.c5.id,
            name: "이전 C5",
            fileName: "old.png",
            referenceDistance: 1,
            reference: ShowcaseFloorPlanSeed.c5.reference
        )
        let repository = DemoFloorPlanCatalogRepository(floorPlans: [incomplete])

        try ShowcaseFloorPlanSeed.prepareCatalog(in: repository)

        XCTAssertEqual(try repository.fetchAll(), [ShowcaseFloorPlanSeed.c5])
    }
}
