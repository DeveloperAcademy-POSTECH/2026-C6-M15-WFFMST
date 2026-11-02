import CQBCore
import SwiftData
import XCTest
@testable import InstructorApp

@MainActor
final class TrainingHistoryRepositoryTests: XCTestCase {
    func testSavedRecordCanBeRestoredFromANewRepository() throws {
        let container = try makeContainer()
        let record = makeRecord(minutesAfterBase: 0)

        try SwiftDataTrainingHistoryRepository(container: container).save(record)

        let restored = try SwiftDataTrainingHistoryRepository(container: container).fetchAll()
        XCTAssertEqual(restored, [record])
    }

    func testFetchAllReturnsLatestStartFirst() throws {
        let repository = SwiftDataTrainingHistoryRepository(container: try makeContainer())
        let older = makeRecord(minutesAfterBase: 0)
        let newer = makeRecord(minutesAfterBase: 60)

        try repository.save(older)
        try repository.save(newer)

        XCTAssertEqual(try repository.fetchAll(), [newer, older])
    }

    func testSavingSameSessionReplacesWithoutDuplicating() throws {
        let repository = SwiftDataTrainingHistoryRepository(container: try makeContainer())
        let original = makeRecord(minutesAfterBase: 0)
        let replacement = TrainingHistoryRecord(
            sessionID: original.sessionID,
            trainingName: "다시 종료한 훈련",
            floorPlan: original.floorPlan,
            floorPlanName: "훈련장 B",
            participantNames: ["강유키"],
            startedAt: original.startedAt,
            endedAt: original.endedAt.addingTimeInterval(30)
        )

        try repository.save(original)
        try repository.save(replacement)

        XCTAssertEqual(try repository.fetchAll(), [replacement])
    }

    func testDeletingRemovesOnlyRequestedSession() throws {
        let repository = SwiftDataTrainingHistoryRepository(container: try makeContainer())
        let first = makeRecord(minutesAfterBase: 0)
        let second = makeRecord(minutesAfterBase: 60)

        try repository.save(first)
        try repository.save(second)
        try repository.delete(sessionID: first.sessionID)

        XCTAssertEqual(try repository.fetchAll(), [second])
    }

    func testRecordTextShortensRosterAndFormatsDuration() {
        let record = makeRecord(minutesAfterBase: 0)

        XCTAssertEqual(record.participantSummary, "강유키 등 3명")
        XCTAssertEqual(record.durationText, "13:24")
        XCTAssertEqual(record.detailText, "훈련장 A · 강유키 등 3명 · \(record.startedAtText)")
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: StoredFloorPlan.self, StoredTrainingHistory.self,
            configurations: configuration
        )
    }

    private func makeRecord(minutesAfterBase minutes: Double) -> TrainingHistoryRecord {
        let startedAt = Date(timeIntervalSince1970: 1_760_000_000 + minutes * 60)
        return TrainingHistoryRecord(
            sessionID: UUID(),
            trainingName: "검사 훈련",
            floorPlan: FloorPlanReference(
                floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000126")!,
                navigationSHA256: "history-hash"
            ),
            floorPlanName: "훈련장 A",
            participantNames: ["강유키", "백매버릭", "새미"],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(13 * 60 + 24)
        )
    }
}
