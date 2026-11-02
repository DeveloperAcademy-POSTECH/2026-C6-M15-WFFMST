import CQBCore
import Foundation

/// 이전 훈련 기록을 지울 때 그 세션의 대원 영상을 Storage와 기기 캐시에서 지운다.
nonisolated protocol TrainingVideoDeleting: Sendable {
    /// 하나라도 지우지 못하면 오류를 던진다. 이미 없는 영상은 지운 것으로 본다.
    func deleteVideos(sessionID: UUID) async throws
}

nonisolated enum TrainingVideoDeletionError: Error, Equatable {
    case failed(count: Int)
}

/// 세션의 녹화 목록에서 대원별 조각 수를 얻어, AAR을 마칠 때 쓰던 `AARVideoLoader.finish`로 지운다.
/// 동선 결과와 Firestore 문서는 지우지 않는다 (docs/issue-126-training-history.md).
nonisolated struct RecordedTrainingVideoDeleter: TrainingVideoDeleting {
    private let recordingRepository: any RecordingRepository
    private let videoLoader: AARVideoLoader

    init(
        recordingRepository: any RecordingRepository,
        videoChunkRepository: any VideoChunkRepository,
        cacheRoot: URL = AARVideoLoader.defaultCacheRoot
    ) {
        self.recordingRepository = recordingRepository
        videoLoader = AARVideoLoader(repository: videoChunkRepository, cacheRoot: cacheRoot)
    }

    func deleteVideos(sessionID: UUID) async throws {
        let recordings = try await recordingRepository.observeRecordings(sessionID: sessionID).firstValue() ?? []
        let failed = await videoLoader.finish(
            recordings.map { (identity: $0.identity, chunkCount: $0.videoChunkCount) }
        )
        guard failed.isEmpty else { throw TrainingVideoDeletionError.failed(count: failed.count) }
    }
}

/// Preview와 로컬 Store 검사에서 서버 없이 삭제 흐름을 확인할 때 쓴다.
nonisolated struct SkippedTrainingVideoDeleter: TrainingVideoDeleting {
    func deleteVideos(sessionID: UUID) async throws {}
}
