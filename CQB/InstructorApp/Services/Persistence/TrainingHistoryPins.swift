import Foundation

/// 이전 훈련 기록에서 고정한 세션 ID를 최근에 고정한 순서로 보관한다.
/// `defaults`가 없으면 메모리에만 둔다(데모 모드, 테스트).
@MainActor
final class TrainingHistoryPins {
    // v2: 순서를 저장하면서 키를 바꿨다. 이미 설치된 기기도 처음 한 번은 킬하우스 UT가 맨 위에 온다.
    private static let key = "trainingHistory.pinnedSessionIDs.v2"
    /// 한 번 자동으로 고정한 세션. 사용자가 고정을 풀면 다시 고정하지 않는다.
    private static let seededKey = "trainingHistory.seededPinnedSessionIDs.v2"
    private let defaults: UserDefaults?
    /// 최근에 고정한 것이 앞
    private(set) var order: [UUID]

    var ids: Set<UUID> { Set(order) }

    /// - Parameter initial: 처음 한 번 고정해 둘 세션. 앞에 둔 것이 위에 온다.
    ///   이미 한 번 고정했던 세션은 다시 고정하지 않는다.
    init(defaults: UserDefaults? = nil, initial: [UUID] = []) {
        self.defaults = defaults
        let stored = defaults?.stringArray(forKey: Self.key).map { $0.compactMap(UUID.init(uuidString:)) }
        // 자동 고정 기록이 없던 예전 저장값은 지금 고정 목록을 이미 고정해 본 것으로 본다.
        let seeded = defaults?.stringArray(forKey: Self.seededKey).map { Set($0.compactMap(UUID.init(uuidString:))) }
            ?? Set(stored ?? [])
        let newIDs = initial.filter { !seeded.contains($0) }
        order = newIDs + (stored ?? []).filter { !newIDs.contains($0) }
        defaults?.set(seeded.union(initial).map(\.uuidString).sorted(), forKey: Self.seededKey)
        save()
    }

    /// 고정하면 맨 앞에 둔다.
    func setPinned(_ isPinned: Bool, sessionID: UUID) {
        order.removeAll { $0 == sessionID }
        if isPinned { order.insert(sessionID, at: 0) }
        save()
    }

    private func save() {
        defaults?.set(order.map(\.uuidString), forKey: Self.key)
    }
}
