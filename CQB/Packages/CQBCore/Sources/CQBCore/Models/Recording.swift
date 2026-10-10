import Foundation

public enum EndReason: String, Codable, Equatable, Sendable {
    case signal, manual, error
}

/// A transfer snapshot, not a correction result or permission to enter AAR.
public enum RecordingState: String, Codable, Equatable, Sendable {
    case recording, uploading, done
}

public enum ReconstructionAttemptState: String, Codable, Equatable, Sendable {
    case pending, running
    /// A result document exists, including one whose TrackResultStatus is failed.
    case completed
    /// Execution failed without producing a result document.
    case failed
    case cancelled
}

/// Construction and decoding do not validate the attempt or change a selection.
public struct ReconstructionAttempt: Codable, Equatable, Sendable {
    public let resultID: UUID
    public let state: ReconstructionAttemptState
    public let result: TrackResultSummary?

    public init(resultID: UUID, state: ReconstructionAttemptState, result: TrackResultSummary? = nil) {
        self.resultID = resultID
        self.state = state
        self.result = result
    }
}

/// A recording that began after receiving a training signal.
/// Construction and decoding do not validate its references, state or authorization.
public struct Recording: Codable, Equatable, Identifiable, Sendable {
    public let identity: TrackIdentity
    public let floorPlan: FloorPlanReference
    public let signalReceivedDeviceAt: Date
    public let recordingStartedDeviceAt: Date
    public let recordingEndedDeviceAt: Date?
    public let endReason: EndReason?
    /// The storage-confirmed upload snapshot is not proof of raw validation.
    public let rawUploaded: Bool
    /// Nil means metadata is not yet available, not that video is optional in the product.
    public let video: VideoInfo?
    public let latestAttempt: ReconstructionAttempt?
    /// An available selection summary. Loading a known selection belongs to the caller.
    public let selectedResult: TrackResultSummary?
    public let state: RecordingState

    public var id: UUID { identity.recordingID }
    public var selectedResultID: UUID? { selectedResult?.resultID }

    public init(identity: TrackIdentity, floorPlan: FloorPlanReference,
                signalReceivedDeviceAt: Date, recordingStartedDeviceAt: Date,
                recordingEndedDeviceAt: Date? = nil, endReason: EndReason? = nil,
                rawUploaded: Bool, video: VideoInfo? = nil,
                latestAttempt: ReconstructionAttempt? = nil, selectedResult: TrackResultSummary? = nil,
                state: RecordingState) {
        self.identity = identity
        self.floorPlan = floorPlan
        self.signalReceivedDeviceAt = signalReceivedDeviceAt
        self.recordingStartedDeviceAt = recordingStartedDeviceAt
        self.recordingEndedDeviceAt = recordingEndedDeviceAt
        self.endReason = endReason
        self.rawUploaded = rawUploaded
        self.video = video
        self.latestAttempt = latestAttempt
        self.selectedResult = selectedResult
        self.state = state
    }
}
