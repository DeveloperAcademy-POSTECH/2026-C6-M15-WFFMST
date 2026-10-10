import Foundation

/// 대원 입장·준비 보고와 준비 현황 구독.
public protocol MemberRepository: Sendable {
    /// 대원 앱: 입장, 준비 상태 보고, 생존 신호에 모두 쓴다. `lastActiveAt`은 서버 시각으로 기록한다.
    /// `pin`은 입장 검증용으로만 저장하며 모델에는 없다.
    func saveMember(_ member: Member, pin: String) async throws

    /// 교관 앱: 세션의 대원 목록이 바뀔 때마다 새 값을 받는다.
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error>
}
