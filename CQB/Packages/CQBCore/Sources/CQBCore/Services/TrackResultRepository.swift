import Foundation

public struct PublishTrackResultRequest: Sendable {
    public let requestID: UUID
    public let identity: TrackIdentity
    public let resultJSON: Data
    public init(requestID: UUID, identity: TrackIdentity, resultJSON: Data) {
        self.requestID = requestID; self.identity = identity; self.resultJSON = resultJSON
    }
}

public struct SelectTrackResultRequest: Equatable, Sendable {
    public let requestID: UUID
    public let identity: TrackIdentity
    public let resultID: UUID
    public let expectedSelectedResultID: UUID?
    public init(requestID: UUID, identity: TrackIdentity, resultID: UUID, expectedSelectedResultID: UUID?) {
        self.requestID = requestID; self.identity = identity; self.resultID = resultID
        self.expectedSelectedResultID = expectedSelectedResultID
    }
}

public enum TrackRepositoryError: Error, Equatable, Sendable {
    case unauthenticated, permissionDenied, notFound, notReady, conflict, notUsable, unavailable
}

/// Identity comes from the authenticated adapter, never from a UID in a request.
/// Separate from local correction and raw upload. Failure diagnostics remain local
/// in this review implementation; no API removes an existing selection on failure.
public protocol TrackResultRepository: Sendable {
    /// Requires a server-confirmed raw and complete, validated result bytes.
    /// Same request + exact bytes retries the original operation. Partial is usable.
    /// Atomically select the first usable result only if there is no selection.
    func publishUsable(_ request: PublishTrackResultRequest) async throws -> ValidatedTrackResult
    /// Explicit compare-and-set, scoped to a single recording. Same request retry
    /// acknowledges the original operation without reapplying a stale selection.
    func select(_ request: SelectTrackResultRequest) async throws
    func loadSelected(for identity: TrackIdentity) async throws -> ValidatedTrackResult?
    func load(resultID: UUID, for identity: TrackIdentity) async throws -> ValidatedTrackResult
}
