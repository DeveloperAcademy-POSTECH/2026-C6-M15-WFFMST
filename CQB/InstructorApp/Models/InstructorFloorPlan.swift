import CQBCore
import Foundation

/// InstructorApp에서 목록·세션 선택에 사용하는 등록 도면이다.
/// `id`는 로컬 카탈로그의 정체성이고, `reference`는 현재 도면 파일 묶음을 가리킨다.
nonisolated struct InstructorFloorPlan: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let fileName: String
    let referenceDistance: Double
    let reference: FloorPlanReference
    let createdAt: Date
    let updatedAt: Date
    var registeredPlan: LocalRegisteredFloorPlan?

    init(
        id: String,
        name: String,
        fileName: String,
        referenceDistance: Double,
        reference: FloorPlanReference = FloorPlanReference(
            floorPlanID: UUID(),
            navigationSHA256: "local-demo"
        ),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        registeredPlan: LocalRegisteredFloorPlan? = nil
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.referenceDistance = referenceDistance
        self.reference = reference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.registeredPlan = registeredPlan
    }
}
