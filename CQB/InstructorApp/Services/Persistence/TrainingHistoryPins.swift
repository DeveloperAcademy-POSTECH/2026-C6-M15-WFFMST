import Foundation

/// 이전 훈련 기록에서 고정한 세션 ID를 보관한다.
/// `defaults`가 없으면 메모리에만 둔다(데모 모드, 테스트).
@MainActor
final class TrainingHistoryPins {
    private static let key = "trainingHistory.pinnedSessionIDs"
    private let defaults: UserDefaults?
    private(set) var ids: Set<UUID>

    /// - Parameter initial: 기기에 저장한 고정 목록이 아직 없을 때 쓸 처음 값
    init(defaults: UserDefaults? = nil, initial: Set<UUID> = []) {
        self.defaults = defaults
        if let stored = defaults?.stringArray(forKey: Self.key) {
            ids = Set(stored.compactMap(UUID.init(uuidString:)))
        } else {
            ids = initial
        }
    }

    func setPinned(_ isPinned: Bool, sessionID: UUID) {
        if isPinned {
            ids.insert(sessionID)
        } else {
            ids.remove(sessionID)
        }
        defaults?.set(ids.map(\.uuidString).sorted(), forKey: Self.key)
    }
}
