import Foundation

public enum TrackDocumentJSON {
    private struct Version: Decodable { let schemaVersion: Int }
    /// Defensive review-implementation limit, not a recommended payload size.
    public static let maximumBytes = 64 * 1_024 * 1_024
    public static func encode<T: Encodable>(_ document: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            let bytes = try encoder.encode(document)
            guard bytes.count <= maximumBytes else { throw TrackValidationError.invalidJSON }
            return bytes
        } catch { throw TrackValidationError.invalidJSON }
    }
    static func decode<T: Decodable>(_ type: T.Type, _ bytes: Data) throws -> T {
        try Task.checkCancellation()
        guard !bytes.isEmpty, bytes.count <= maximumBytes,
              String(data: bytes, encoding: .utf8) != nil else { throw TrackValidationError.invalidJSON }
        let decoder = JSONDecoder()
        let version: Int
        do { version = try decoder.decode(Version.self, from: bytes).schemaVersion }
        catch { throw TrackValidationError.invalidJSON }
        guard version == 1 else { throw TrackValidationError.unsupportedSchema(version) }
        do { return try decoder.decode(type, from: bytes) }
        catch { throw TrackValidationError.invalidJSON }
    }
}

public struct ValidatedRawTrack: Sendable {
    public let document: RawTrackDocument
    public let bytes: Data
    public let sha256: String
    fileprivate init(document: RawTrackDocument, bytes: Data) {
        self.document = document; self.bytes = bytes; self.sha256 = FloorPlanJSON.sha256(bytes)
    }
}

public struct ValidatedTrackResult: Sendable {
    public let document: TrackResultDocument
    public let bytes: Data
    public let sha256: String
    fileprivate init(document: TrackResultDocument, bytes: Data) {
        self.document = document; self.bytes = bytes; self.sha256 = FloorPlanJSON.sha256(bytes)
    }
}

/// Structural/coverage checks, not a correction algorithm or proof of accuracy.
/// Uses point lookup only; a free vertex does not prove a collision-free edge.
public enum TrackDocumentValidator {
    public static func raw(_ bytes: Data, floorPlan: ValidatedFloorPlan) throws -> ValidatedRawTrack {
        let raw = try TrackDocumentJSON.decode(RawTrackDocument.self, bytes)
        guard raw.floorPlan == floorPlan.reference else { throw TrackValidationError.referenceMismatch }
        _ = try TrackCoordinateTransform(floorPlan: floorPlan, start: raw.startPose.positionNormalized,
            directionPoint: raw.startPose.directionPointNormalized,
            cameraDirectionRadians: raw.startPose.cameraDirectionRadians)
        guard !raw.samples.isEmpty, raw.recordingStartOffsetSeconds.isFinite,
              raw.recordingStartOffsetSeconds >= 0,
              [raw.originMeters.x, raw.originMeters.y, raw.originMeters.z].allSatisfy(\.isFinite) else {
            throw TrackValidationError.invalidRaw
        }
        var previous: TrackRawSample?
        var hasObservedValidPosition = false
        for sample in raw.samples {
            try Task.checkCancellation()
            guard sample.time.isFinite, sample.time >= 0, sample.arTimestamp.isFinite, sample.arTimestamp >= 0,
                  (sample.time + raw.recordingStartOffsetSeconds).isFinite,
                  sample.arPosition.count == 3, sample.arPosition.allSatisfy(\.isFinite), sample.segment >= 0,
                  (sample.trackingState == .normal) == (sample.relativeMeters != nil) else {
                throw TrackValidationError.invalidRaw
            }
            if let p = previous {
                guard sample.time >= p.time, sample.arTimestamp >= p.arTimestamp, sample.segment >= p.segment else {
                    throw TrackValidationError.invalidRaw
                }
                // Initial acquisition is not recovery from a previously tracked
                // route. Preserve a leading unknown prefix without renumbering it.
                if hasObservedValidPosition, p.relativeMeters == nil,
                   sample.relativeMeters != nil, sample.segment <= p.segment {
                    throw TrackValidationError.invalidRaw
                }
            }
            if let point = sample.relativeMeters {
                guard point.x.isFinite, point.y.isFinite,
                      matchesRelativeMeters(point.x, position: sample.arPosition[0], origin: raw.originMeters.x),
                      matchesRelativeMeters(point.y, position: sample.arPosition[2], origin: raw.originMeters.z) else {
                    throw TrackValidationError.invalidRaw
                }
                hasObservedValidPosition = true
            }
            previous = sample
        }
        try Task.checkCancellation()
        return ValidatedRawTrack(document: raw, bytes: bytes)
    }

    private static func matchesRelativeMeters(_ relative: Double, position: Double, origin: Double) -> Bool {
        let doubleDifference = position - origin
        guard doubleDifference.isFinite else { return false }
        if abs(doubleDifference - relative) <= 1e-6 { return true }

        // ARKit/PoC subtract Float coordinates before promoting the result to
        // Double. Accept that exact arithmetic path as well, without widening
        // the tolerance to every value in a magnitude-dependent ULP interval.
        // Do not silently quantize arbitrary Double inputs to Float.
        guard let floatPosition = Float(exactly: position),
              let floatOrigin = Float(exactly: origin) else { return false }
        let floatDifference = floatPosition - floatOrigin
        guard floatDifference.isFinite else { return false }
        return abs(Double(floatDifference) - relative) <= 1e-6
    }

    public static func result(_ bytes: Data, raw: ValidatedRawTrack,
                              floorPlan: ValidatedFloorPlan) throws -> ValidatedTrackResult {
        let result = try TrackDocumentJSON.decode(TrackResultDocument.self, bytes)
        let source = raw.document
        guard result.identity == source.identity, result.floorPlan == source.floorPlan,
              result.floorPlan == floorPlan.reference else { throw TrackValidationError.referenceMismatch }
        guard result.sourceRawSHA256 == raw.sha256 else { throw TrackValidationError.rawHashMismatch }
        guard [result.algorithm.name, result.algorithm.version, result.algorithm.settingsID]
            .allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw TrackValidationError.invalidResult
        }
        let offset = source.recordingStartOffsetSeconds
        let start = source.samples[0].time + offset, end = source.samples[source.samples.count - 1].time + offset
        let ranges = result.unresolvedIntervals
        var previousRange: TrackUnresolvedInterval?
        for range in ranges {
            try Task.checkCancellation()
            guard range.from.isFinite, range.to.isFinite, range.from >= start, range.to <= end,
                  range.from <= range.to, range.from != range.to || range.bounds == .closed else {
                throw TrackValidationError.invalidInterval
            }
            if let p = previousRange,
               range.from < p.to || (range.from == p.to && p.bounds.includesEnd && range.bounds.includesStart) {
                throw TrackValidationError.invalidInterval
            }
            previousRange = range
        }

        // Nil samples and raw segment changes are genuine breaks, even if the
        // solver only reports the resume index. Do not join a line over them.
        var breaks: [(Double, Double)] = []
        var lastValid: TrackRawSample?
        var lost = false
        for sample in source.samples {
            try Task.checkCancellation()
            if sample.relativeMeters == nil { lost = true; continue }
            if let p = lastValid, lost || p.segment != sample.segment {
                breaks.append((p.time + offset, sample.time + offset))
            }
            lastValid = sample; lost = false
        }
        var previous: TrackResultVertex?
        var usable = false, breakIndex = 0, intervalIndex = 0, gapRangeIndex = 0, vertexRangeIndex = 0
        var runs: [(Double, Double)] = []
        for vertex in result.vertices {
            try Task.checkCancellation()
            guard vertex.t.isFinite, vertex.t >= start, vertex.t <= end, vertex.part >= 0,
                  !floorPlan.isBlocked(at: vertex.point) else { throw TrackValidationError.invalidResult }
            while vertexRangeIndex < ranges.count && (ranges[vertexRangeIndex].to < vertex.t ||
                (ranges[vertexRangeIndex].to == vertex.t && !ranges[vertexRangeIndex].bounds.includesEnd)) {
                vertexRangeIndex += 1
            }
            if vertexRangeIndex < ranges.count, ranges[vertexRangeIndex].contains(vertex.t) {
                throw TrackValidationError.invalidResult
            }
            if let index = vertex.sampleIndex {
                guard source.samples.indices.contains(index), source.samples[index].relativeMeters != nil else {
                    throw TrackValidationError.invalidResult
                }
                if vertex.provenance == .correctedSample,
                   abs(vertex.t - (source.samples[index].time + offset)) > 1e-8 {
                    throw TrackValidationError.invalidResult
                }
            } else if vertex.provenance == .correctedSample { throw TrackValidationError.invalidResult }
            if let p = previous {
                guard vertex.t >= p.t else { throw TrackValidationError.invalidResult }
                if p.part == vertex.part {
                    // Positive-duration gaps are open at their valid endpoints:
                    // an edge starting at the resume time cannot cross that old
                    // gap. Advance to the next one instead of letting it hide a
                    // later break. Equal-time breaks remain inclusive, however.
                    while breakIndex < breaks.count {
                        let gap = breaks[breakIndex]
                        guard gap.1 < p.t || (gap.1 == p.t && gap.0 < gap.1) else { break }
                        breakIndex += 1
                    }
                    if breakIndex < breaks.count {
                        let gap = breaks[breakIndex]
                        if (gap.0 < vertex.t && gap.1 > p.t) ||
                            (gap.0 == gap.1 && p.t <= gap.0 && vertex.t >= gap.1) {
                            throw TrackValidationError.disconnectedPath
                        }
                    }
                    while intervalIndex < ranges.count && ranges[intervalIndex].to <= p.t { intervalIndex += 1 }
                    if intervalIndex < ranges.count,
                       ranges[intervalIndex].from < vertex.t && ranges[intervalIndex].to > p.t {
                        throw TrackValidationError.disconnectedPath
                    }
                    if vertex.point != p.point { usable = true }
                    runs[runs.count - 1].1 = vertex.t
                } else {
                    // A disconnected pair needs an explicit unresolved interval,
                    // even when both endpoints happen to have raw positions.
                    while gapRangeIndex < ranges.count && ranges[gapRangeIndex].to < vertex.t { gapRangeIndex += 1 }
                    guard gapRangeIndex < ranges.count, ranges[gapRangeIndex].from <= p.t,
                          ranges[gapRangeIndex].to >= vertex.t else {
                        throw TrackValidationError.invalidInterval
                    }
                    runs.append((vertex.t, vertex.t))
                }
            } else { runs.append((vertex.t, vertex.t)) }
            previous = vertex
        }
        switch result.status {
        case .failed:
            guard result.vertices.isEmpty, !ranges.isEmpty else { throw TrackValidationError.invalidStatus }
        case .done:
            guard usable, ranges.isEmpty, result.failureReason == nil, breaks.isEmpty,
                  source.samples.allSatisfy({ $0.relativeMeters != nil }) else { throw TrackValidationError.invalidStatus }
        case .partial:
            guard usable, !ranges.isEmpty, result.failureReason == nil else { throw TrackValidationError.invalidStatus }
        }
        // Coverage means represented time, not vertices.count / samples.count.
        // Sparse solver vertices may represent intermediate valid samples.
        var runIndex = 0, rangeIndex = 0
        for sample in source.samples {
            try Task.checkCancellation()
            let t = sample.time + offset
            while runIndex < runs.count && runs[runIndex].1 < t { runIndex += 1 }
            while rangeIndex < ranges.count &&
                (ranges[rangeIndex].to < t || (ranges[rangeIndex].to == t && !ranges[rangeIndex].bounds.includesEnd)) {
                rangeIndex += 1
            }
            let unresolved = rangeIndex < ranges.count && ranges[rangeIndex].contains(t)
            let represented = runIndex < runs.count && runs[runIndex].0 <= t && t <= runs[runIndex].1
            guard sample.relativeMeters == nil ? unresolved : (represented || unresolved) else {
                throw TrackValidationError.invalidStatus
            }
        }
        try Task.checkCancellation()
        return ValidatedTrackResult(document: result, bytes: bytes)
    }
}
