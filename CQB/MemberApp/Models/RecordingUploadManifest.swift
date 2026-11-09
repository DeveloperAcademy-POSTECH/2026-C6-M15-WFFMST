import CQBCore
import Foundation

/// MemberApp 전용 업로드 체크포인트. 공통 데이터 계약에는 포함하지 않는다.
nonisolated struct RecordingUploadManifest: Codable, Sendable {
    let identity: TrackIdentity
    var videoChunkCount: Int?
    var uploadedVideoChunkIndexes: Set<Int>
    var uploadedTrackResult: Bool
    /// 음향 후보(#172)를 올렸다. 이 항목이 없던 예전 기록표는 false로 읽는다.
    var uploadedSoundCandidates: Bool

    init(identity: TrackIdentity, videoChunkCount: Int? = nil,
         uploadedVideoChunkIndexes: Set<Int> = [], uploadedTrackResult: Bool = false,
         uploadedSoundCandidates: Bool = false) {
        self.identity = identity
        self.videoChunkCount = videoChunkCount
        self.uploadedVideoChunkIndexes = uploadedVideoChunkIndexes
        self.uploadedTrackResult = uploadedTrackResult
        self.uploadedSoundCandidates = uploadedSoundCandidates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identity = try container.decode(TrackIdentity.self, forKey: .identity)
        videoChunkCount = try container.decodeIfPresent(Int.self, forKey: .videoChunkCount)
        uploadedVideoChunkIndexes = try container.decode(Set<Int>.self, forKey: .uploadedVideoChunkIndexes)
        uploadedTrackResult = try container.decode(Bool.self, forKey: .uploadedTrackResult)
        uploadedSoundCandidates = try container.decodeIfPresent(Bool.self, forKey: .uploadedSoundCandidates) ?? false
    }
}
