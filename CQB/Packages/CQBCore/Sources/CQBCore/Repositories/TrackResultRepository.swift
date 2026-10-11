import Foundation

/// 기록당 하나인 보정 결과 `result.json` 올리기·받기.
public protocol TrackResultRepository: Sendable {
    /// 대원 앱: 보정 결과를 올린다. 경로는 `result.identity`로 정한다.
    func upload(_ result: TrackResultDocument) async throws

    /// 교관 앱: 기록의 보정 결과를 받는다. 없으면 `RepositoryError.notFound`.
    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument
}
