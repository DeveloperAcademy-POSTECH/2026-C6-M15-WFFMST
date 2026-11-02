import AVFoundation

nonisolated enum AARVideoComposerError: Error, Equatable {
    /// 조각 파일에 영상 트랙이 없다
    case missingVideoTrack(URL)
}

/// 영상 조각들을 하나의 영상처럼 이어 붙인다. 타임라인 이동은 이어 붙인 영상에서 `seek` 한 번으로 한다.
/// 오디오가 있는 조각은 영상과 같은 위치에 이어 붙이고, 오디오가 없는 조각은 무음 구간으로 둔다.
nonisolated enum AARVideoComposer {
    static func compose(_ chunks: [URL]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard !chunks.isEmpty,
              let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              )
        else { return composition }

        var audioTrack: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for (index, url) in chunks.enumerated() {
            let asset = AVURLAsset(url: url)
            guard let videoSource = try await asset.loadTracks(withMediaType: .video).first else {
                throw AARVideoComposerError.missingVideoTrack(url)
            }
            let videoRange = try await videoSource.load(.timeRange)
            try videoTrack.insertTimeRange(videoRange, of: videoSource, at: cursor)
            if index == 0 {
                // 세로 촬영 등 회전 정보는 첫 조각을 따른다.
                videoTrack.preferredTransform = try await videoSource.load(.preferredTransform)
            }

            if let audioSource = try await asset.loadTracks(withMediaType: .audio).first {
                if audioTrack == nil {
                    audioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                }
                if let audioTrack {
                    let sourceRange = try await audioSource.load(.timeRange)
                    let duration = CMTimeCompare(sourceRange.duration, videoRange.duration) <= 0
                        ? sourceRange.duration
                        : videoRange.duration
                    try audioTrack.insertTimeRange(
                        CMTimeRange(start: sourceRange.start, duration: duration),
                        of: audioSource,
                        at: cursor
                    )
                }
            }
            cursor = cursor + videoRange.duration
        }
        return composition
    }
}
