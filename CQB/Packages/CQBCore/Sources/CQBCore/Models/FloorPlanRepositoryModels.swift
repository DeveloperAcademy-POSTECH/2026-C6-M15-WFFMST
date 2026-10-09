import Foundation

/// Ready library entry. Ownership comes from the authenticated service context,
/// never from a UID supplied in a registration request. Not a Firebase DTO.
public struct FloorPlanSummary: Equatable, Sendable {
    public let name: String
    public let reference: FloorPlanReference

    public init(name: String, reference: FloorPlanReference) {
        self.name = name
        self.reference = reference
    }
}

/// Retain the same ID, name, reference and exact file bytes until the outcome is
/// known. A timeout/cancellation does not imply that a write was rolled back.
public struct RegisterFloorPlanRequest: Sendable {
    public let requestID: UUID
    public let name: String
    public let reference: FloorPlanReference
    public let files: FloorPlanFiles

    public init(requestID: UUID, name: String, reference: FloorPlanReference, files: FloorPlanFiles) {
        self.requestID = requestID
        self.name = name
        self.reference = reference
        self.files = files
    }
}

public struct FloorPlanPage: Sendable {
    public let items: [FloorPlanSummary]
    /// Opaque, scoped to this authenticated library. Do not parse or share it.
    public let nextCursor: String?

    public init(items: [FloorPlanSummary], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct CreateFloorPlanSessionRequest: Equatable, Sendable {
    public let requestID: UUID
    public let name: String
    public let floorPlan: FloorPlanReference

    public init(requestID: UUID, name: String, floorPlan: FloorPlanReference) {
        self.requestID = requestID
        self.name = name
        self.floorPlan = floorPlan
    }
}

/// Only the immutable map binding produced when a session is created, not the
/// full Session model (PIN, members, training status/signals are outside scope).
public struct SessionFloorPlanBinding: Equatable, Sendable {
    public let sessionID: UUID
    public let name: String
    public let floorPlan: FloorPlanReference

    public init(sessionID: UUID, name: String, floorPlan: FloorPlanReference) {
        self.sessionID = sessionID
        self.name = name
        self.floorPlan = floorPlan
    }
}

/// File validation errors remain FloorPlanValidationError. Cancellation remains
/// CancellationError; neither is converted into an empty list or success.
public enum FloorPlanRepositoryError: Error, Equatable, Sendable {
    case unauthenticated
    case permissionDenied
    case notFound
    case notReady
    case conflict
    case invalidRequest
    case invalidCursor
    /// Transient failure; for writes the outcome may be unknown. Retry unchanged.
    case unavailable
}
