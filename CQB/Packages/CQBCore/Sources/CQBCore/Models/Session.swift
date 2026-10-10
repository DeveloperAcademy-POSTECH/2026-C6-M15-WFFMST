import Foundation

/// A reported session phase. This enum does not execute or authorize transitions.
public enum SessionStatus: String, Codable, Equatable, Sendable {
    /// Session preparation is being configured.
    case preparing
    /// Waiting for the training start command.
    case waiting
    case running
    case ended
}

/// A session snapshot with the floor plan fixed at creation.
/// Construction and decoding do not validate its contents or establish access.
public struct Session: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let pin: String
    public let name: String
    public let status: SessionStatus
    /// Repository-confirmed server time, not a temporary client timestamp.
    public let createdAt: Date
    /// Repository-confirmed server time of the training start, when known.
    public let startedAt: Date?
    /// Repository-confirmed server time of the training end, when known.
    public let endedAt: Date?
    public let excludedMemberIDs: [UUID]
    public let floorPlan: FloorPlanReference

    public init(id: UUID, pin: String, name: String, status: SessionStatus,
                createdAt: Date, startedAt: Date? = nil, endedAt: Date? = nil,
                excludedMemberIDs: [UUID], floorPlan: FloorPlanReference) {
        self.id = id
        self.pin = pin
        self.name = name
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.excludedMemberIDs = excludedMemberIDs
        self.floorPlan = floorPlan
    }

    /// The existing map-binding projection; no replacement map is resolved.
    public var floorPlanBinding: SessionFloorPlanBinding {
        SessionFloorPlanBinding(sessionID: id, name: name, floorPlan: floorPlan)
    }
}
