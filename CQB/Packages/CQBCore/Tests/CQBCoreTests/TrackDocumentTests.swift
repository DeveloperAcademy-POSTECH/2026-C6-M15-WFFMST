import Foundation
import Testing
@testable import CQBCore

@Test("TrackIdentity가 세션과 대원, 기록 식별자를 보존한다")
func trackIdentityCodableRoundTrip() throws {
    let identity = TrackIdentity(
        sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
        memberID: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
        recordingID: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
    )

    let decoded = try codableRoundTrip(identity)

    #expect(decoded == identity)
}

@Test("TrackResultDocument가 단일 보정 결과 계약을 Codable 왕복한다")
func trackResultDocumentCodableRoundTrip() throws {
    let document = makeTrackResultDocument()

    let decoded = try codableRoundTrip(document)

    #expect(decoded == document)
    #expect(decoded.vertices.map(\.t) == [0, 1.5])
}

@Test("TrackResultDocument는 resultID 없이 TrackIdentity로 기록에 연결된다")
func trackResultDocumentWithoutResultID() throws {
    let document = makeTrackResultDocument()

    let json = try encodedJSONObject(document)
    let identityJSON = try #require(json["identity"] as? [String: Any])

    #expect(json["resultID"] == nil)
    #expect(json["selectedResultID"] == nil)
    let encodedRecordingID = try #require(identityJSON["recordingID"] as? String)
    #expect(UUID(uuidString: encodedRecordingID) == document.identity.recordingID)
}

@Test("서로 다른 recordingID를 가진 결과는 구분된다")
func trackResultsAreSeparatedByRecordingID() {
    let first = makeTrackResultDocument(recordingID: UUID())
    let second = makeTrackResultDocument(recordingID: UUID())

    #expect(first.identity.recordingID != second.identity.recordingID)
    #expect(first.identity != second.identity)
}

private func makeTrackResultDocument(
    recordingID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
) -> TrackResultDocument {
    TrackResultDocument(
        identity: TrackIdentity(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            memberID: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
            recordingID: recordingID
        ),
        floorPlan: FloorPlanReference(
            floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000404")!,
            navigationSHA256: "navigation-sha256"
        ),
        sourceRawSHA256: "raw-track-sha256",
        algorithm: TrackAlgorithmIdentity(
            name: "map-matcher",
            version: "1.0.0",
            settingsID: "default"
        ),
        status: .partial,
        vertices: [
            TrackResultVertex(
                t: 0,
                point: ImagePoint(x: 120, y: 240),
                part: 0,
                sampleIndex: 0,
                provenance: .correctedSample
            ),
            TrackResultVertex(
                t: 1.5,
                point: ImagePoint(x: 140, y: 250),
                part: 0,
                sampleIndex: nil,
                provenance: .generated
            ),
        ],
        sampleCoverage: [
            TrackSampleCoverage(
                samples: TrackSampleRange(from: 0, through: 4),
                vertices: TrackVertexRange(from: 0, through: 1)
            ),
            TrackSampleCoverage(
                samples: TrackSampleRange(from: 5, through: 6),
                vertices: nil
            ),
        ],
        unresolvedIntervals: [
            TrackUnresolvedInterval(
                from: 1.5,
                to: 2.0,
                bounds: .startOpen,
                reason: .trackingLost,
                samples: TrackSampleRange(from: 5, through: 6),
                sourceReason: "sensor unavailable"
            ),
        ],
        searchIncomplete: true,
        warnings: [.trackingLost, .searchIncomplete]
    )
}
