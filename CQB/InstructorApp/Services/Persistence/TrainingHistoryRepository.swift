import Foundation

/// 지난 훈련 기록을 기기에 보관하는 경계다.
@MainActor
protocol TrainingHistoryRepository {
    /// 시작 시각 최신순으로 돌려준다.
    func fetchAll() throws -> [TrainingHistoryRecord]
    /// 같은 세션 ID가 있으면 덮어쓴다.
    func save(_ record: TrainingHistoryRecord) throws
    func delete(sessionID: UUID) throws
}

@MainActor
final class UnavailableTrainingHistoryRepository: TrainingHistoryRepository {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func fetchAll() throws -> [TrainingHistoryRecord] { throw error }
    func save(_ record: TrainingHistoryRecord) throws { throw error }
    func delete(sessionID: UUID) throws { throw error }
}

/// Preview, 데모 모드와 로컬 Store 검사에서 사용하는 메모리 기록 저장소다.
@MainActor
final class InMemoryTrainingHistoryRepository: TrainingHistoryRepository {
    private var stored: [TrainingHistoryRecord]
    var fetchError: Error?
    var saveError: Error?
    var deleteError: Error?

    init(records: [TrainingHistoryRecord] = []) {
        stored = records
    }

    func fetchAll() throws -> [TrainingHistoryRecord] {
        if let fetchError { throw fetchError }
        return stored.sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ record: TrainingHistoryRecord) throws {
        if let saveError { throw saveError }
        if let index = stored.firstIndex(where: { $0.sessionID == record.sessionID }) {
            stored[index] = record
        } else {
            stored.append(record)
        }
    }

    func delete(sessionID: UUID) throws {
        if let deleteError { throw deleteError }
        stored.removeAll { $0.sessionID == sessionID }
    }
}
