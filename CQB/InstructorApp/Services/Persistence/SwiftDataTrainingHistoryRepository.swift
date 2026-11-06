import CQBCore
import Foundation
import SwiftData

@Model
final class StoredTrainingHistory {
    @Attribute(.unique) var sessionID: UUID
    var trainingName: String
    var floorPlanID: UUID
    var navigationSHA256: String
    var floorPlanName: String
    var participantNames: [String]
    var startedAt: Date
    var endedAt: Date

    init(from record: TrainingHistoryRecord) {
        sessionID = record.sessionID
        trainingName = record.trainingName
        floorPlanID = record.floorPlan.floorPlanID
        navigationSHA256 = record.floorPlan.navigationSHA256
        floorPlanName = record.floorPlanName
        participantNames = record.participantNames
        startedAt = record.startedAt
        endedAt = record.endedAt
    }

    func update(from record: TrainingHistoryRecord) {
        trainingName = record.trainingName
        floorPlanID = record.floorPlan.floorPlanID
        navigationSHA256 = record.floorPlan.navigationSHA256
        floorPlanName = record.floorPlanName
        participantNames = record.participantNames
        startedAt = record.startedAt
        endedAt = record.endedAt
    }

    func record() -> TrainingHistoryRecord {
        TrainingHistoryRecord(
            sessionID: sessionID,
            trainingName: trainingName,
            floorPlan: FloorPlanReference(
                floorPlanID: floorPlanID,
                navigationSHA256: navigationSHA256
            ),
            floorPlanName: floorPlanName,
            participantNames: participantNames,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }
}

nonisolated final class SwiftDataTrainingHistoryRepository: TrainingHistoryRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func fetchAll() throws -> [TrainingHistoryRecord] {
        let descriptor = FetchDescriptor<StoredTrainingHistory>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse), SortDescriptor(\.endedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.record() }
    }

    func save(_ record: TrainingHistoryRecord) throws {
        if let stored = try stored(sessionID: record.sessionID) {
            stored.update(from: record)
        } else {
            context.insert(StoredTrainingHistory(from: record))
        }
        try context.save()
    }

    func delete(sessionID: UUID) throws {
        guard let stored = try stored(sessionID: sessionID) else { return }
        context.delete(stored)
        try context.save()
    }

    private func stored(sessionID: UUID) throws -> StoredTrainingHistory? {
        let descriptor = FetchDescriptor<StoredTrainingHistory>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        return try context.fetch(descriptor).first
    }
}
