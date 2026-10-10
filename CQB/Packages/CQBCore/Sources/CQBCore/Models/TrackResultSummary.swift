import Foundation

/// Result metadata without route geometry or sample diagnostics.
/// Construction and decoding do not prove that the underlying document was validated.
public struct TrackResultSummary: Codable, Equatable, Sendable {
    public let identity: TrackIdentity
    public let resultID: UUID
    public let floorPlan: FloorPlanReference
    public let sourceRawSHA256: String
    public let algorithm: TrackAlgorithmIdentity
    public let status: TrackResultStatus
    public let searchIncomplete: Bool
    public let warnings: [TrackResultWarning]
    public let failureReason: TrackUnresolvedReason?
    public let finishedAt: Date?

    public init(identity: TrackIdentity, resultID: UUID, floorPlan: FloorPlanReference,
                sourceRawSHA256: String, algorithm: TrackAlgorithmIdentity, status: TrackResultStatus,
                searchIncomplete: Bool, warnings: [TrackResultWarning],
                failureReason: TrackUnresolvedReason? = nil, finishedAt: Date? = nil) {
        self.identity = identity
        self.resultID = resultID
        self.floorPlan = floorPlan
        self.sourceRawSHA256 = sourceRawSHA256
        self.algorithm = algorithm
        self.status = status
        self.searchIncomplete = searchIncomplete
        self.warnings = warnings
        self.failureReason = failureReason
        self.finishedAt = finishedAt
    }

    public init(validatedResult: ValidatedTrackResult, finishedAt: Date? = nil) {
        let document = validatedResult.document
        self.init(identity: document.identity, resultID: document.resultID,
                  floorPlan: document.floorPlan, sourceRawSHA256: document.sourceRawSHA256,
                  algorithm: document.algorithm, status: document.status,
                  searchIncomplete: document.searchIncomplete, warnings: document.warnings,
                  failureReason: document.failureReason, finishedAt: finishedAt)
    }
}
