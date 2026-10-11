import Foundation

/// 영상 조각 `chunk_NNNN.mp4` 올리기와 기록 전체 영상 받기·지우기. `index`는 0부터 시작한다.
public protocol VideoChunkRepository: Sendable {
    /// 대원 앱: 녹화하면서 만든 10초 조각을 하나씩 올린다. 20MB를 넘으면 `RepositoryError.fileTooLarge`.
    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws

    /// 교관 앱: 기록의 조각을 모두 `directory`에 받고, 재생 순서대로 파일 위치를 돌려준다.
    /// `Recording.state == .done`이 된 뒤 `Recording.videoChunkCount`를 넘겨 한 번 부른다.
    /// 조각이 하나라도 없으면 `RepositoryError.notFound`.
    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL]

    /// 교관 앱: AAR이 끝나면 기록의 조각을 모두 Storage에서 지운다. 이미 없는 조각은 건너뛴다.
    /// 삭제가 실패해도 Storage 수명 주기 규칙(1일)이 남은 영상을 지운다.
    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws
}
