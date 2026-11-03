import Foundation

/// 기록당 하나인 음향 후보 `sound-candidates.json` 올리기·받기.
public protocol SoundCandidateRepository: Sendable {
    /// 대원 앱: 음향 후보를 올린다. 경로는 `document.identity`로 정한다. 같은 기록에 다시 올리면 덮어쓴다.
    func upload(_ document: SoundCandidateDocument) async throws

    /// 교관 앱: 기록의 음향 후보를 받는다. 없으면 `RepositoryError.notFound`이며 "분석 안 됨"으로 처리한다.
    /// 받은 문서의 `identity`가 요청과 다르면 `RepositoryError.integrityMismatch`.
    func download(_ identity: TrackIdentity) async throws -> SoundCandidateDocument
}
