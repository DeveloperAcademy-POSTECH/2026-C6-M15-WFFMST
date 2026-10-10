import Foundation

/// 대원 앱과 교관 앱이 공유하는 최소 대원 정보다.
/// 인증 UID와 입장 검증용 PIN은 Firebase 어댑터에서 관리한다.
public struct Member: Codable, Sendable, Identifiable {
    /// 대원 기기에 저장하고 같은 세션에 재입장할 때 재사용한다.
    public let id: UUID
    public let sessionID: UUID
    public let name: String

    /// 출발점 설정과 추적 준비를 마친 뒤 대원 앱이 보고하는 준비 상태다.
    public let isReady: Bool

    /// 대원이 마지막 활동을 알린 서버 시각이며 기록 시작 전 연결 상태 판단에 사용한다.
    /// 구체적인 연결 끊김 판단 시간은 이 모델을 사용하는 쪽에서 결정한다.
    public let lastActiveAt: Date

    public init(
        id: UUID,
        sessionID: UUID,
        name: String,
        isReady: Bool,
        lastActiveAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.name = name
        self.isReady = isReady
        self.lastActiveAt = lastActiveAt
    }
}
