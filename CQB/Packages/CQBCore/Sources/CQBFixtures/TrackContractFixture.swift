import Foundation
import CQBCore

/// Bridges hand-authored review samples to schema-1 documents in memory.
/// Does not run V13 or rewrite the original fixture files/hashes.
public enum TrackContractFixture {
    public enum Case: String, CaseIterable, Sendable {
        case normal, trackingGap = "tracking-gap", searchLimit = "search-limit"
        case insufficientMovement = "insufficient-movement"
    }

    public static func rawDocument(_ example: Case) throws -> RawTrackDocument {
        guard let file = MinimalTrackFixture.File(rawValue: "\(example.rawValue)-raw.json") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let raw = try JSONDecoder().decode(RawExample.self, from: MinimalTrackFixture.data(for: file))
        return RawTrackDocument(identity: TrackIdentity(sessionID: raw.sessionID, memberID: raw.memberID,
            recordingID: raw.recordingID), floorPlan: raw.floorPlan, originMeters: raw.originMeters,
            startPose: raw.startPose, recordingStartOffsetSeconds: 0.4, samples: raw.samples)
    }

    public static func rawJSON(_ example: Case) throws -> Data { try TrackDocumentJSON.encode(rawDocument(example)) }

    public static func resultDocument(_ example: Case) throws -> TrackResultDocument {
        let expectations = try JSONDecoder().decode(Expectations.self, from: MinimalTrackFixture.data(for: .expectations))
        guard let expected = expectations.cases.first(where: { $0.id == example.rawValue }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let raw = try rawDocument(example)
        return TrackResultDocument(identity: raw.identity, resultID: expected.resultID,
            floorPlan: raw.floorPlan, sourceRawSHA256: FloorPlanJSON.sha256(try rawJSON(example)),
            algorithm: TrackAlgorithmIdentity(name: "hand-authored-not-v13-execution",
                version: "minimal-v1", settingsID: "manual-expectations"), status: expected.status,
            vertices: expected.vertices.map {
                TrackResultVertex(t: $0.t, point: ImagePoint(x: $0.x, y: $0.y), part: $0.part,
                    sampleIndex: $0.sampleIndex, provenance: $0.provenance)
            }, sampleCoverage: coverage(for: example),
            unresolvedIntervals: try expected.unresolvedIntervals.map { interval in
                guard let samples = diagnosticRange(for: example) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return TrackUnresolvedInterval(from: interval.from, to: interval.to,
                    bounds: interval.bounds, reason: interval.reason, samples: samples)
            }, searchIncomplete: example == .searchLimit,
            warnings: expected.warnings, failureReason: expected.failureReason)
    }

    public static func resultJSON(_ example: Case) throws -> Data { try TrackDocumentJSON.encode(resultDocument(example)) }

    // These are explicit, hand-authored expectations for the unchanged review samples,
    // not an inference from timestamps or sparse vertices and not a production V13 adapter.
    // Diagnostic ranges include their known boundary samples; that does not make the
    // boundary coordinates missing. Coverage alone says which raw indices have a route.
    private static func coverage(for example: Case) -> [TrackSampleCoverage] {
        switch example {
        case .normal:
            return [.init(samples: .init(from: 0, through: 2), vertices: .init(from: 0, through: 2))]
        case .trackingGap:
            return [.init(samples: .init(from: 0, through: 1), vertices: .init(from: 0, through: 1)),
                .init(samples: .init(from: 2, through: 3), vertices: nil),
                .init(samples: .init(from: 4, through: 5), vertices: .init(from: 2, through: 3))]
        case .searchLimit:
            return [.init(samples: .init(from: 0, through: 1), vertices: .init(from: 0, through: 1)),
                .init(samples: .init(from: 2, through: 3), vertices: nil)]
        case .insufficientMovement:
            return [.init(samples: .init(from: 0, through: 1), vertices: nil)]
        }
    }

    private static func diagnosticRange(for example: Case) -> TrackSampleRange? {
        switch example {
        case .normal: return nil
        case .trackingGap: return .init(from: 1, through: 4)
        case .searchLimit: return .init(from: 1, through: 3)
        case .insufficientMovement: return .init(from: 0, through: 1)
        }
    }

    private struct RawExample: Decodable {
        let sessionID: UUID; let memberID: UUID; let recordingID: UUID
        let floorPlan: FloorPlanReference; let originMeters: TrackOrigin
        let startPose: TrackStartPose; let samples: [TrackRawSample]
    }
    private struct Expectations: Decodable {
        // The original fixture has its own review format, not the current wire schema.
        // Keep decoding it separately so contract changes do not rewrite fixture bytes/hashes.
        struct DisplayInterval: Decodable {
            let from: Double; let to: Double; let bounds: TrackIntervalBounds
            let reason: TrackUnresolvedReason
        }
        struct Vertex: Decodable {
            let t: Double; let x: Double; let y: Double; let part: Int
            let sampleIndex: Int?; let provenance: TrackPointProvenance
        }
        struct Item: Decodable {
            let id: String; let resultID: UUID; let status: TrackResultStatus
            let vertices: [Vertex]; let unresolvedIntervals: [DisplayInterval]
            let warnings: [TrackResultWarning]; let failureReason: TrackUnresolvedReason?
        }
        let cases: [Item]
    }
}
