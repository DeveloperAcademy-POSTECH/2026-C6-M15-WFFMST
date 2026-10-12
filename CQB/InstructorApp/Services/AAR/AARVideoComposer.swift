import AVFoundation

nonisolated enum AARVideoComposerError: Error, Equatable {
    /// 조각 파일에 영상 트랙이 없다
    case missingVideoTrack(URL)
}

/// 영상 조각들을 하나의 영상처럼 이어 붙인다. 타임라인 이동은 이어 붙인 영상에서 `seek` 한 번으로 한다.
/// 소리는 넣지 않는다 (영상 녹음 여부 미정).
nonisolated enum AARVideoComposer {
    static func compose(_ chunks: [URL]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard !chunks.isEmpty,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return composition }

        var cursor = CMTime.zero
        for (index, url) in chunks.enumerated() {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw AARVideoComposerError.missingVideoTrack(url)
            }
            let range = try await source.load(.timeRange)
            try track.insertTimeRange(range, of: source, at: cursor)
            if index == 0 {
                // 세로 촬영 등 회전 정보는 첫 조각을 따른다.
                track.preferredTransform = try await source.load(.preferredTransform)
            }
            cursor = cursor + range.duration
        }
        return composition
    }
}
