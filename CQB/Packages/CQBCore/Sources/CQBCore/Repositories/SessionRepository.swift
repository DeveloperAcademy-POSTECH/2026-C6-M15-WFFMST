import Foundation

/// 세션 생성·검색·상태 변경과 시작·종료 신호 구독. PIN으로 세션을 찾는 일도 맡는다.
public protocol SessionRepository: Sendable {
    /// 교관 앱: PIN과 세션을 함께 만든다. PIN은 앱이 정하며, 이미 쓰이고 있으면 `RepositoryError.pinTaken`.
    func createSession(_ session: Session) async throws

    /// 대원 앱: PIN으로 세션을 찾는다. 없으면 `RepositoryError.notFound`.
    func session(forPin pin: String) async throws -> Session

    /// 교관 앱: 세션 상태를 바꾼다.
    /// `running`이면 `startedAt`을 서버 시각으로 기록하고, `ended`면 PIN을 다시 쓸 수 있게 지운다.
    func updateStatus(of session: Session, to status: SessionStatus) async throws

    /// 대원 앱: 교관의 시작·종료 신호(`status` 변경)를 실시간으로 받는다.
    /// 신호를 놓치지 않도록 입장 직후부터 `ended`를 받을 때까지 구독한다. 처음 구독하면 현재 값이 한 번 바로 온다.
    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error>
}
