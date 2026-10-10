import Foundation

/// Video metadata; construction and decoding do not validate the values.
public struct VideoInfo: Codable, Equatable, Sendable {
    public let codec: String
    public let width: Int
    public let height: Int
    public let fps: Int
    /// Target split length; each chunk carries its actual duration separately.
    public let chunkSeconds: TimeInterval
    /// Nil while the final number of chunks is not known.
    public let totalChunks: Int?
    /// The number of uploads confirmed complete by storage.
    public let uploadedChunks: Int

    public init(codec: String, width: Int, height: Int, fps: Int,
                chunkSeconds: TimeInterval, totalChunks: Int? = nil, uploadedChunks: Int) {
        self.codec = codec
        self.width = width
        self.height = height
        self.fps = fps
        self.chunkSeconds = chunkSeconds
        self.totalChunks = totalChunks
        self.uploadedChunks = uploadedChunks
    }
}

/// A chunk's time is relative to recording start, not session start.
/// Construction and decoding do not validate timing, upload state or references.
public struct VideoChunk: Codable, Equatable, Identifiable, Sendable {
    public struct ID: Codable, Hashable, Sendable {
        public let identity: TrackIdentity
        public let index: Int

        public init(identity: TrackIdentity, index: Int) {
            self.identity = identity
            self.index = index
        }
    }

    public let identity: TrackIdentity
    /// Zero-based within this recording; the same index can occur in another recording.
    public let index: Int
    public let startSeconds: TimeInterval
    public let durationSeconds: TimeInterval
    /// Storage-confirmed upload time, absent before that confirmation is available.
    public let uploadedAt: Date?

    public var id: ID { ID(identity: identity, index: index) }

    public init(identity: TrackIdentity, index: Int, startSeconds: TimeInterval,
                durationSeconds: TimeInterval, uploadedAt: Date? = nil) {
        self.identity = identity
        self.index = index
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.uploadedAt = uploadedAt
    }
}
