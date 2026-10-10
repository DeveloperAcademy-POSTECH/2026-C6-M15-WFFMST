import Foundation

/// A member's map placement before capture, using normalized image coordinates.
/// Validation and the measured capture-start camera heading are separate inputs.
public struct MemberStartConfiguration: Codable, Equatable, Sendable {
    public let floorPlan: FloorPlanReference
    public let positionNormalized: NormalizedPoint
    public let directionPointNormalized: NormalizedPoint

    public init(floorPlan: FloorPlanReference, positionNormalized: NormalizedPoint,
                directionPointNormalized: NormalizedPoint) {
        self.floorPlan = floorPlan
        self.positionNormalized = positionNormalized
        self.directionPointNormalized = directionPointNormalized
    }

    /// The caller supplies the measured capture-start heading and validates the
    /// alignment against this configuration's floor plan. No angle is inferred.
    public func trackStartPose(cameraDirectionRadians: Double) -> TrackStartPose {
        TrackStartPose(positionNormalized: positionNormalized,
                       directionPointNormalized: directionPointNormalized,
                       cameraDirectionRadians: cameraDirectionRadians)
    }
}

/// A participant snapshot scoped to one session, not an authentication identity.
/// Construction and decoding do not validate its contents or establish access.
public struct Member: Codable, Equatable, Sendable, Identifiable {
    /// Session participant UUID, distinct from the server's authentication UID.
    public let id: UUID
    public let sessionID: UUID
    public let name: String
    public let displayName: String
    /// Repository-confirmed server time, not a temporary client timestamp.
    public let joinedAt: Date
    /// Server time minus device time, in seconds. May be negative; nil is unmeasured.
    public let clockOffsetToServer: TimeInterval?
    /// Nil when the placement has not been set or has been invalidated.
    public let startConfiguration: MemberStartConfiguration?

    public init(id: UUID, sessionID: UUID, name: String, displayName: String,
                joinedAt: Date, clockOffsetToServer: TimeInterval? = nil,
                startConfiguration: MemberStartConfiguration? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.name = name
        self.displayName = displayName
        self.joinedAt = joinedAt
        self.clockOffsetToServer = clockOffsetToServer
        self.startConfiguration = startConfiguration
    }
}

/// Reported device facts, not a computed readiness decision or proof of access.
/// Construction and decoding do not validate the report or its freshness.
public struct DeviceStatus: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let memberID: UUID
    /// Reports valid position and direction setup on the session's map revision.
    public let startPointSet: Bool
    /// Reports tracking preparation; raw leading nil samples do not imply readiness.
    public let trackingReady: Bool
    public let recording: Bool
    /// Repository-confirmed server time for the report, not a device clock reading.
    public let updatedAt: Date

    public init(sessionID: UUID, memberID: UUID, startPointSet: Bool,
                trackingReady: Bool, recording: Bool, updatedAt: Date) {
        self.sessionID = sessionID
        self.memberID = memberID
        self.startPointSet = startPointSet
        self.trackingReady = trackingReady
        self.recording = recording
        self.updatedAt = updatedAt
    }
}
