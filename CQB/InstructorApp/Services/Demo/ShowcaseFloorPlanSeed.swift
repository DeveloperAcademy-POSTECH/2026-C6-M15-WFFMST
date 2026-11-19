import CQBCore
import Foundation

/// 쇼케이스 빌드의 도면 관리 목록에 항상 준비해 둘 C5 도면이다.
/// 파일은 번들에 복제하지 않고 Firebase Storage의 불변 참조를 사용한다.
enum ShowcaseFloorPlanSeed {
    static let c5FloorPlanID = UUID(uuidString: "67140CC6-309D-4776-B3A7-28C8D86EEF80")!

    static let c5 = InstructorFloorPlan(
        id: c5FloorPlanID.uuidString,
        name: "C5",
        fileName: "original.png",
        referenceDistance: 47.308977509201426,
        reference: FloorPlanReference(
            floorPlanID: c5FloorPlanID,
            navigationSHA256: "9577be8375a2005e84ba483ffad36d11583daea5d55e88b51e52c21cc8795b92"
        ),
        worldMap: WorldMapReference(
            worldMapID: UUID(uuidString: "8142C879-5BB8-4E6D-B4A0-AF5FF2BAECAA")!,
            setupSHA256: "3862b4ca1a30077dd23a58bd0baa4fb40eddef2a2cbf8f8d8f1ce7201b8158f5",
            floorPlan: FloorPlanReference(
                floorPlanID: c5FloorPlanID,
                navigationSHA256: "9577be8375a2005e84ba483ffad36d11583daea5d55e88b51e52c21cc8795b92"
            )
        ),
        createdAt: Date(timeIntervalSince1970: 1_793_890_306.565894),
        updatedAt: Date(timeIntervalSince1970: 1_793_890_306.565894)
    )

    @MainActor
    static func prepareCatalog(in repository: any FloorPlanCatalogRepository) throws {
        let floorPlans = try repository.fetchAll()
        if floorPlans.first(where: { $0.id == c5.id }) != c5 {
            try repository.save(c5)
        }
        for floorPlan in floorPlans where floorPlan.id != c5.id {
            try repository.delete(id: floorPlan.id)
        }
    }
}
