import Foundation

// Review implementation, schema 1. Not the legacy PoC v15 capture format.
// Construction/decoding does not validate these transfer values.
public struct TrackIdentity: Codable, Hashable, Sendable {
    public var sessionID: UUID
    public var memberID: UUID
    public var recordingID: UUID
    public init(sessionID: UUID, memberID: UUID, recordingID: UUID) {
        self.sessionID = sessionID; self.memberID = memberID; self.recordingID = recordingID
    }
}

public struct TrackMeters: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct TrackOrigin: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}

public struct TrackStartPose: Codable, Equatable, Sendable {
    public var positionNormalized: NormalizedPoint
    public var directionPointNormalized: NormalizedPoint
    public var cameraDirectionRadians: Double
    public init(positionNormalized: NormalizedPoint, directionPointNormalized: NormalizedPoint,
                cameraDirectionRadians: Double) {
        self.positionNormalized = positionNormalized; self.directionPointNormalized = directionPointNormalized
        self.cameraDirectionRadians = cameraDirectionRadians
    }
}

public enum TrackTrackingState: String, Codable, Sendable {
    case normal, initializing, excessiveMotion, insufficientFeatures, relocalizing, notAvailable, limited, unknown
}

public struct TrackRawSample: Codable, Equatable, Sendable {
    public var time: Double
    public var arTimestamp: Double
    public var arPosition: [Double]
    public var relativeMeters: TrackMeters?
    public var trackingState: TrackTrackingState
    public var segment: Int
    public init(time: Double, arTimestamp: Double, arPosition: [Double], relativeMeters: TrackMeters?,
                trackingState: TrackTrackingState, segment: Int) {
        self.time = time; self.arTimestamp = arTimestamp; self.arPosition = arPosition
        self.relativeMeters = relativeMeters; self.trackingState = trackingState; self.segment = segment
    }
}

public struct RawTrackDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var identity: TrackIdentity
    public var floorPlan: FloorPlanReference
    public var originMeters: TrackOrigin
    public var startPose: TrackStartPose
    /// Known session offset supplied by the capture/synchronization boundary.
    public var recordingStartOffsetSeconds: Double
    public var samples: [TrackRawSample]
    public init(identity: TrackIdentity, floorPlan: FloorPlanReference, originMeters: TrackOrigin,
                startPose: TrackStartPose, recordingStartOffsetSeconds: Double, samples: [TrackRawSample]) {
        self.identity = identity; self.floorPlan = floorPlan; self.originMeters = originMeters
        self.startPose = startPose; self.recordingStartOffsetSeconds = recordingStartOffsetSeconds; self.samples = samples
    }
}

public enum TrackResultStatus: String, Codable, Sendable { case done, partial, failed }
/// Provenance is not confidence/accuracy. Do not infer it from sampleIndex alone.
public enum TrackPointProvenance: String, Codable, Sendable { case unspecified, correctedSample, generated }
public enum TrackUnresolvedReason: String, Codable, Sendable {
    case trackingLost, connectionUnverified, searchLimit, insufficientMovement, noCandidate, unknown
}
public enum TrackIntervalBounds: String, Codable, Sendable {
    case open = "()", closed = "[]", startOpen = "(]", endOpen = "[)"
    public var includesStart: Bool { self == .closed || self == .endOpen }
    public var includesEnd: Bool { self == .closed || self == .startOpen }
}
/// Diagnostics do not change route geometry, selection or completion status.
public enum TrackResultWarning: String, Codable, Sendable {
    case trackingLost, connectionUnverified, searchIncomplete
    /// The solver explicitly reported ambiguous initial-heading candidates.
    /// Absence is not proof of a reliable heading; never infer from rotation alone.
    case headingAmbiguous
}

public struct TrackUnresolvedInterval: Codable, Equatable, Sendable {
    public var from: Double
    public var to: Double
    public var bounds: TrackIntervalBounds
    public var reason: TrackUnresolvedReason
    public init(from: Double, to: Double, bounds: TrackIntervalBounds, reason: TrackUnresolvedReason) {
        self.from = from; self.to = to; self.bounds = bounds; self.reason = reason
    }
    public func contains(_ time: Double) -> Bool {
        (time > from || (time == from && bounds.includesStart)) &&
        (time < to || (time == to && bounds.includesEnd))
    }
}

public struct TrackResultVertex: Codable, Equatable, Sendable {
    public var t: Double
    public var point: ImagePoint
    public var part: Int
    public var sampleIndex: Int?
    public var provenance: TrackPointProvenance
    public init(t: Double, point: ImagePoint, part: Int, sampleIndex: Int?,
                provenance: TrackPointProvenance = .unspecified) {
        self.t = t; self.point = point; self.part = part; self.sampleIndex = sampleIndex; self.provenance = provenance
    }
}

public struct TrackAlgorithmIdentity: Codable, Equatable, Sendable {
    public var name: String
    public var version: String
    public var settingsID: String
    public init(name: String, version: String, settingsID: String) {
        self.name = name; self.version = version; self.settingsID = settingsID
    }
}

public struct TrackResultDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var identity: TrackIdentity
    public var resultID: UUID
    public var floorPlan: FloorPlanReference
    public var sourceRawSHA256: String
    public var algorithm: TrackAlgorithmIdentity
    public var status: TrackResultStatus
    public var vertices: [TrackResultVertex]
    public var unresolvedIntervals: [TrackUnresolvedInterval]
    public var searchIncomplete: Bool
    public var warnings: [TrackResultWarning]
    public var failureReason: TrackUnresolvedReason?
    public init(identity: TrackIdentity, resultID: UUID, floorPlan: FloorPlanReference, sourceRawSHA256: String,
                algorithm: TrackAlgorithmIdentity, status: TrackResultStatus, vertices: [TrackResultVertex],
                unresolvedIntervals: [TrackUnresolvedInterval], searchIncomplete: Bool,
                warnings: [TrackResultWarning], failureReason: TrackUnresolvedReason? = nil) {
        self.identity = identity; self.resultID = resultID; self.floorPlan = floorPlan
        self.sourceRawSHA256 = sourceRawSHA256; self.algorithm = algorithm; self.status = status
        self.vertices = vertices; self.unresolvedIntervals = unresolvedIntervals
        self.searchIncomplete = searchIncomplete; self.warnings = warnings; self.failureReason = failureReason
    }
}

public enum TrackValidationError: Error, Equatable, Sendable {
    case invalidJSON, unsupportedSchema(Int), referenceMismatch, rawHashMismatch
    case invalidRaw, invalidResult, invalidInterval, invalidStatus, disconnectedPath
}
