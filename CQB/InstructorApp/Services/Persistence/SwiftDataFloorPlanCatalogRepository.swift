import CQBCore
import Foundation
import SwiftData

@Model
final class StoredFloorPlan {
    @Attribute(.unique) var catalogID: String
    var name: String
    var fileName: String
    var referenceDistance: Double
    var floorPlanID: UUID
    var navigationSHA256: String
    var createdAt: Date
    var updatedAt: Date

    init(from floorPlan: InstructorFloorPlan) {
        catalogID = floorPlan.id
        name = floorPlan.name
        fileName = floorPlan.fileName
        referenceDistance = floorPlan.referenceDistance
        floorPlanID = floorPlan.reference.floorPlanID
        navigationSHA256 = floorPlan.reference.navigationSHA256
        createdAt = floorPlan.createdAt
        updatedAt = floorPlan.updatedAt
    }

    func update(from floorPlan: InstructorFloorPlan) {
        name = floorPlan.name
        fileName = floorPlan.fileName
        referenceDistance = floorPlan.referenceDistance
        floorPlanID = floorPlan.reference.floorPlanID
        navigationSHA256 = floorPlan.reference.navigationSHA256
        updatedAt = floorPlan.updatedAt
    }

    func floorPlan() -> InstructorFloorPlan {
        InstructorFloorPlan(
            id: catalogID,
            name: name,
            fileName: fileName,
            referenceDistance: referenceDistance,
            reference: FloorPlanReference(
                floorPlanID: floorPlanID,
                navigationSHA256: navigationSHA256
            ),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

nonisolated final class SwiftDataFloorPlanCatalogRepository: FloorPlanCatalogRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func fetchAll() throws -> [InstructorFloorPlan] {
        let descriptor = FetchDescriptor<StoredFloorPlan>(
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.catalogID)]
        )
        return try context.fetch(descriptor).map { $0.floorPlan() }
    }

    func save(_ floorPlan: InstructorFloorPlan) throws {
        let catalogID = floorPlan.id
        let descriptor = FetchDescriptor<StoredFloorPlan>(
            predicate: #Predicate { $0.catalogID == catalogID }
        )
        if let stored = try context.fetch(descriptor).first {
            stored.update(from: floorPlan)
        } else {
            context.insert(StoredFloorPlan(from: floorPlan))
        }
        try context.save()
    }
}
