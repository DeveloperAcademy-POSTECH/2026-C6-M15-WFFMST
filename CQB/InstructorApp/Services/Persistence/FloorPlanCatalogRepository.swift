import Foundation

/// InstructorApp에서 등록한 도면 목록을 기기에 보관하는 경계다.
/// 도면 파일 전송은 `FloorPlanFileRepository`가 계속 담당한다.
@MainActor
protocol FloorPlanCatalogRepository {
    func fetchAll() throws -> [InstructorFloorPlan]
    func save(_ floorPlan: InstructorFloorPlan) throws
}

@MainActor
final class UnavailableFloorPlanCatalogRepository: FloorPlanCatalogRepository {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func fetchAll() throws -> [InstructorFloorPlan] { throw error }
    func save(_ floorPlan: InstructorFloorPlan) throws { throw error }
}
