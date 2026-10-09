import Foundation

public enum FloorPlanGeometry {
    public static func imagePoint(from point: NormalizedPoint, width: Int, height: Int) throws -> ImagePoint {
        try validateSize(width: width, height: height)
        guard isNormalized(point) else { throw FloorPlanValidationError.invalidCoordinate }
        return ImagePoint(x: point.x * Double(width), y: point.y * Double(height))
    }

    /// Right/bottom boundary is allowed for scale/outline conversion, not cell lookup.
    public static func normalizedPoint(from point: ImagePoint, width: Int, height: Int) throws -> NormalizedPoint {
        try validateSize(width: width, height: height)
        guard isImagePoint(point, width: width, height: height) else {
            throw FloorPlanValidationError.invalidCoordinate
        }
        return NormalizedPoint(x: point.x / Double(width), y: point.y / Double(height))
    }

    public static func pixelsPerMeter(for scale: MapScale, width: Int, height: Int) throws -> Double {
        try validateSize(width: width, height: height)
        guard isImagePoint(scale.a, width: width, height: height),
              isImagePoint(scale.b, width: width, height: height),
              scale.meters.isFinite, scale.meters > 0, scale.meters <= 1_000 else {
            throw FloorPlanValidationError.invalidScale
        }
        let distance = hypot(scale.b.x - scale.a.x, scale.b.y - scale.a.y)
        let result = distance / scale.meters
        guard distance >= 10, result.isFinite else { throw FloorPlanValidationError.invalidScale }
        return result
    }

    static func validateSize(width: Int, height: Int) throws {
        guard (1...4_096).contains(width), (1...4_096).contains(height) else {
            throw FloorPlanValidationError.invalidImage
        }
    }

    static func isNormalized(_ point: NormalizedPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    static func isImagePoint(_ point: ImagePoint, width: Int, height: Int) -> Bool {
        point.x.isFinite && point.y.isFinite && point.x >= 0 && point.y >= 0
            && point.x <= Double(width) && point.y <= Double(height)
    }

    // Same polygon rules/tolerances as LocalFloorPlanGeometry. This is outline
    // geometry, NOT a policy for route segments crossing grid edges/corners.
    static func validateOutline(_ points: [NormalizedPoint]) throws {
        guard (3...512).contains(points.count), points.allSatisfy(isNormalized) else {
            throw FloorPlanValidationError.invalidOutline
        }
        var twiceArea = 0.0
        for i in points.indices {
            try Task.checkCancellation()
            let next = (i + 1) % points.count
            let a = points[i], b = points[next], c = points[(i + 2) % points.count]
            guard hypot(a.x - b.x, a.y - b.y) > 1e-9 else { throw FloorPlanValidationError.invalidOutline }
            if abs(cross(a, b, c)) <= 1e-12,
               (a.x - b.x) * (c.x - b.x) + (a.y - b.y) * (c.y - b.y) > 0 {
                throw FloorPlanValidationError.invalidOutline
            }
            twiceArea += a.x * b.y - b.x * a.y
            for j in (i + 1)..<points.count {
                let otherNext = (j + 1) % points.count
                if next == j || otherNext == i { continue }
                if intersects(a, b, points[j], points[otherNext]) { throw FloorPlanValidationError.invalidOutline }
            }
        }
        guard abs(twiceArea) > 1e-12 else { throw FloorPlanValidationError.invalidOutline }
    }

    static func contains(_ point: NormalizedPoint, polygon: [NormalizedPoint]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[previous]
            if onSegment(point, a, b) { return true }
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            previous = i
        }
        return inside
    }

    private static func cross(_ a: NormalizedPoint, _ b: NormalizedPoint, _ c: NormalizedPoint) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    private static func onSegment(_ p: NormalizedPoint, _ a: NormalizedPoint, _ b: NormalizedPoint) -> Bool {
        abs(cross(a, b, p)) <= 1e-12 && p.x >= min(a.x, b.x) - 1e-12 && p.x <= max(a.x, b.x) + 1e-12
            && p.y >= min(a.y, b.y) - 1e-12 && p.y <= max(a.y, b.y) + 1e-12
    }
    private static func intersects(_ a: NormalizedPoint, _ b: NormalizedPoint,
                                   _ c: NormalizedPoint, _ d: NormalizedPoint) -> Bool {
        let abC = cross(a, b, c), abD = cross(a, b, d), cdA = cross(c, d, a), cdB = cross(c, d, b)
        if ((abC > 0 && abD < 0) || (abC < 0 && abD > 0))
            && ((cdA > 0 && cdB < 0) || (cdA < 0 && cdB > 0)) { return true }
        return onSegment(c, a, b) || onSegment(d, a, b) || onSegment(a, c, d) || onSegment(b, c, d)
    }
}
