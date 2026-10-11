import Foundation

/// 대원 입장·준비 보고와 준비 현황 구독.
public protocol MemberRepository: Sendable {
    /// 대원 앱: 세션에 입장한다. `lastActiveAt`은 서버 시각으로 기록한다.
    /// - PIN이 없거나 다른 세션을 가리키면 `RepositoryError.notFound`.
    /// - 훈련이 이미 시작했거나 끝났으면(`running`, `ended`) `RepositoryError.sessionClosed`. `preparing`, `waiting`에서만 입장한다.
    /// `pin`은 입장 검증용으로만 저장하며 모델에는 없다.
    func join(_ member: Member, pin: String) async throws

    /// 대원 앱: 준비 상태 보고와 생존 신호에 쓴다. `isReady`와 `lastActiveAt`(서버 시각)만 바꾼다.
    func updateReadiness(of member: Member) async throws

    /// 교관 앱: 세션의 대원 목록이 바뀔 때마다 새 값을 받는다.
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error>
}
