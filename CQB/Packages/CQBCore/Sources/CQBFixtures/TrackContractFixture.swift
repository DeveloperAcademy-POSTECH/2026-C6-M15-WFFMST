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
            }, unresolvedIntervals: expected.unresolvedIntervals, searchIncomplete: example == .searchLimit,
            warnings: expected.warnings, failureReason: expected.failureReason)
    }

    public static func resultJSON(_ example: Case) throws -> Data { try TrackDocumentJSON.encode(resultDocument(example)) }

    private struct RawExample: Decodable {
        let sessionID: UUID; let memberID: UUID; let recordingID: UUID
        let floorPlan: FloorPlanReference; let originMeters: TrackOrigin
        let startPose: TrackStartPose; let samples: [TrackRawSample]
    }
    private struct Expectations: Decodable {
        struct Vertex: Decodable {
            let t: Double; let x: Double; let y: Double; let part: Int
            let sampleIndex: Int?; let provenance: TrackPointProvenance
        }
        struct Item: Decodable {
            let id: String; let resultID: UUID; let status: TrackResultStatus
            let vertices: [Vertex]; let unresolvedIntervals: [TrackUnresolvedInterval]
            let warnings: [TrackResultWarning]; let failureReason: TrackUnresolvedReason?
        }
        let cases: [Item]
    }
}
