import Foundation

/// Local calculation boundary only. A V13 adapter will implement this separately;
/// this protocol does not authorize an upload or a change to the selected result.
/// Check raw/map references before work, preserve the raw, and propagate cancellation.
/// Return a new result ID for recalculation. Validate encoded output before publication.
public protocol TrackReconstructing: Sendable {
    func reconstruct(raw: ValidatedRawTrack, floorPlan: ValidatedFloorPlan,
                     resultID: UUID) async throws -> TrackResultDocument
}
