import Foundation

/// Runtime boundary values, not the RawTrack/Reconstruction storage schema.
/// x = AR X - origin X; y = AR Z - origin Z, in meters (not image pixels).
public struct RelativeTrackMeters: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum TrackCoordinateError: Error, Equatable, Sendable {
    case invalidAlignment
    case invalidCoordinate
    case invalidTime
    case invalidVertex
    case timeOrder
}

/// A selected solver vertex whose coordinates are ALREADY corrected image pixels.
/// time is seconds since recording start, not session start or AR uptime.
public struct RecordingRouteVertex: Equatable, Sendable {
    public let point: ImagePoint
    public let time: Double
    public let sampleIndex: Int?
    public let part: Int

    public init(point: ImagePoint, time: Double, sampleIndex: Int?, part: Int) {
        self.point = point; self.time = time; self.sampleIndex = sampleIndex; self.part = part
    }
}

/// Produced only by the timeline conversion. Not accepted as its input, so a
/// session-time vertex cannot accidentally have the recording offset added again.
public struct SessionRouteVertex: Equatable, Sendable {
    public let point: ImagePoint
    public let sessionTime: Double
    public let sampleIndex: Int?
    public let part: Int

    init(point: ImagePoint, sessionTime: Double, sampleIndex: Int?, part: Int) {
        self.point = point; self.sessionTime = sessionTime
        self.sampleIndex = sampleIndex; self.part = part
    }
}

/// One selected result only. Never concatenate results/recordings before conversion:
/// a part number is local to a result, not a session-wide segment identifier.
public struct SessionRouteTimeline: Sendable {
    public let vertices: [SessionRouteVertex]

    init(vertices: [SessionRouteVertex]) { self.vertices = vertices }

    /// Contiguous runs, not grouping by part ID: [0, 1, 0] stays three runs.
    /// Render each run independently; no inferred line across a part boundary.
    public var continuousParts: [[SessionRouteVertex]] {
        var parts: [[SessionRouteVertex]] = []
        for vertex in vertices {
            if parts.last?.last?.part == vertex.part {
                parts[parts.count - 1].append(vertex)
            } else {
                parts.append([vertex])
            }
        }
        return parts
    }
}
