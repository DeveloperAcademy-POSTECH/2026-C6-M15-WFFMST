import Foundation

/// Initial AR-to-image projection, NOT obstacle correction or a V13 replacement.
/// Retains only geometry/reference, not the potentially large image/mask buffers.
public struct TrackCoordinateTransform: Sendable {
    public let floorPlan: FloorPlanReference
    public let startPixels: ImagePoint
    public let pixelsPerMeter: Double
    public let rotationDegrees: Double
    public let rotationRadians: Double

    /// cameraDirectionRadians must be the measured start-camera heading in the
    /// same X/Z convention as RelativeTrackMeters. No firstWalk/zero fallback.
    public init(floorPlan: ValidatedFloorPlan, start: NormalizedPoint,
                directionPoint: NormalizedPoint, cameraDirectionRadians: Double) throws {
        let width = floorPlan.manifest.imageWidth, height = floorPlan.manifest.imageHeight
        let anchor = try FloorPlanGeometry.imagePoint(from: start, width: width, height: height)
        let toward = try FloorPlanGeometry.imagePoint(from: directionPoint, width: width, height: height)
        try floorPlan.validateStart(at: anchor)
        guard cameraDirectionRadians.isFinite,
              hypot(toward.x - anchor.x, toward.y - anchor.y) >= 10 else {
            throw TrackCoordinateError.invalidAlignment
        }
        // Match V13 RouteHeading.rotation: >=10px direction and [0, 360) degrees.
        let degrees = (atan2(toward.y - anchor.y, toward.x - anchor.x) - cameraDirectionRadians) * 180 / .pi
        guard degrees.isFinite else { throw TrackCoordinateError.invalidAlignment }
        let rotation = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        self.floorPlan = floorPlan.reference
        self.startPixels = anchor
        self.pixelsPerMeter = floorPlan.pixelsPerMeter
        self.rotationDegrees = rotation
        self.rotationRadians = rotation * .pi / 180
    }

    /// Raw drift can project outside the image; do not clamp or pretend it is a
    /// corrected/free point. The correction/validation boundary handles that later.
    public func project(_ meters: RelativeTrackMeters) throws -> ImagePoint {
        guard meters.x.isFinite, meters.y.isFinite else { throw TrackCoordinateError.invalidCoordinate }
        let cosine = cos(rotationRadians), sine = sin(rotationRadians)
        let point = ImagePoint(
            x: startPixels.x + pixelsPerMeter * (cosine * meters.x - sine * meters.y),
            y: startPixels.y + pixelsPerMeter * (sine * meters.x + cosine * meters.y))
        guard point.x.isFinite, point.y.isFinite else { throw TrackCoordinateError.invalidCoordinate }
        return point
    }
}

public enum TrackTimeline {
    /// Converts time only; deliberately accepts no scale or transform parameter.
    /// The caller supplies a known session-relative offset, not a device timestamp.
    /// This is not a full result validator (identity, raw hash, status, collision).
    public static func sessionTimeline(from vertices: [RecordingRouteVertex],
                                       recordingStartOffset: Double) throws -> SessionRouteTimeline {
        try Task.checkCancellation()
        guard recordingStartOffset.isFinite, recordingStartOffset >= 0 else {
            throw TrackCoordinateError.invalidTime
        }
        var result: [SessionRouteVertex] = []
        result.reserveCapacity(vertices.count)
        var previousTime: Double?
        for vertex in vertices {
            try Task.checkCancellation()
            guard vertex.point.x.isFinite, vertex.point.y.isFinite,
                  vertex.sampleIndex.map({ $0 >= 0 }) ?? true, vertex.part >= 0 else { throw TrackCoordinateError.invalidVertex }
            let time = vertex.time + recordingStartOffset
            guard vertex.time.isFinite, vertex.time >= 0, time.isFinite else {
                throw TrackCoordinateError.invalidTime
            }
            // Preserve PoC's nondecreasing order, including equal timestamps.
            // Never sort/reindex to hide malformed input or change source indices.
            if let previousTime, vertex.time < previousTime { throw TrackCoordinateError.timeOrder }
            previousTime = vertex.time
            result.append(SessionRouteVertex(point: vertex.point, sessionTime: time,
                sampleIndex: vertex.sampleIndex, part: vertex.part))
        }
        try Task.checkCancellation()
        return SessionRouteTimeline(vertices: result)
    }
}
