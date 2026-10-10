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
        try TrackResultCoverageValidator.validate(result, raw: source, floorPlan: floorPlan)
        try Task.checkCancellation()
        return ValidatedTrackResult(document: result, bytes: bytes)
    }
}
