import Foundation

/// 서버에 기록된 세션 진행 단계다.
/// 상태 전이와 권한 검사는 세션을 저장하는 Repository가 담당한다.
public enum SessionStatus: String, Codable, Sendable {
    case preparing
    case waiting
    case running
    case ended
}

/// 교관 앱과 대원 앱이 공유하는 최소 세션 정보다.
public struct Session: Codable, Sendable, Identifiable {
    public let id: UUID
    public let pin: String
    public let name: String
    public let status: SessionStatus

    /// 모든 기록 시간의 서버 기준으로 사용하는 세션 시작 시각이다.
    /// 개별 기록의 시작점과는 별도로 연결해야 하며 세션 시작 전에는 nil이다.
    public let startedAt: Date?

    /// 세션 생성 시 고정한다. 다른 도면을 사용하려면 새 세션을 생성한다.
    public let floorPlan: FloorPlanReference

    public init(
        id: UUID,
        pin: String,
        name: String,
        status: SessionStatus,
        startedAt: Date? = nil,
        floorPlan: FloorPlanReference
    ) {
        self.id = id
        self.pin = pin
        self.name = name
        self.status = status
        self.startedAt = startedAt
        self.floorPlan = floorPlan
    }
}
