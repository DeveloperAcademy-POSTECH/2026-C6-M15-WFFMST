import CQBCore
import Foundation

/// MemberApp 전용 업로드 체크포인트. 공통 데이터 계약에는 포함하지 않는다.
nonisolated struct RecordingUploadManifest: Codable, Sendable {
    let identity: TrackIdentity
    let videoChunkCount: Int
    var uploadedVideoChunkIndexes: Set<Int>
    var uploadedTrackResult: Bool

    init(identity: TrackIdentity, videoChunkCount: Int,
         uploadedVideoChunkIndexes: Set<Int> = [], uploadedTrackResult: Bool = false) {
        self.identity = identity
        self.videoChunkCount = videoChunkCount
        self.uploadedVideoChunkIndexes = uploadedVideoChunkIndexes
        self.uploadedTrackResult = uploadedTrackResult
    }
}
