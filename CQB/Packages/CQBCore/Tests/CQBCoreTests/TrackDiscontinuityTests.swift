import Foundation
import Testing
import CQBCore
import CQBFixtures

/// Hand-authored times/parts: no expected gaps are computed by the validator.
struct TrackDiscontinuityTests {
    private func example(segments: [Int], times: [Double]? = nil, missing: Set<Int> = [],
                         vertices: [Int], parts: [Int], gaps: [(Int, Int)]) throws
        -> (map: ValidatedFloorPlan, raw: ValidatedRawTrack, result: TrackResultDocument) {
        precondition(vertices.count == parts.count)
        let map = try contractTrackMap()
        var source = try TrackContractFixture.rawDocument(.normal)
        source.originMeters = .init(x: 0, y: 0, z: 0)
        source.recordingStartOffsetSeconds = 0.4
        source.samples = segments.indices.map { i in
            let time = times?[i] ?? Double(i)
            return .init(time: time, arTimestamp: 100 + time, arPosition: [Double(i), 0, 0],
                relativeMeters: missing.contains(i) ? nil : .init(x: Double(i), y: 0),
                trackingState: missing.contains(i) ? .notAvailable : .normal, segment: segments[i])
        }
        let raw = try TrackDocumentValidator.raw(TrackDocumentJSON.encode(source), floorPlan: map)
        var result = try TrackContractFixture.resultDocument(.normal)
        result.sourceRawSHA256 = raw.sha256
        result.status = .partial
        result.vertices = zip(vertices, parts).map { index, part in
            .init(t: source.samples[index].time + 0.4,
                  point: .init(x: 100 + Double(index) * 5, y: 120), part: part,
                  sampleIndex: index, provenance: .correctedSample)
        }
        result.unresolvedIntervals = gaps.map {
            .init(from: source.samples[$0.0].time + 0.4, to: source.samples[$0.1].time + 0.4,
                bounds: .open, reason: .trackingLost, samples: .init(from: $0.0, through: $0.1))
        }
        // Describe the route CLAIMED by the test input, even when it illegally
        // crosses raw breaks. Do not derive expected coverage from the validator.
        result.sampleCoverage = []
        var nextSample = 0, firstVertex = 0
        while firstVertex < vertices.count {
            var lastVertex = firstVertex
            while lastVertex + 1 < vertices.count && parts[lastVertex + 1] == parts[firstVertex] {
                lastVertex += 1
            }
            if nextSample < vertices[firstVertex] {
                result.sampleCoverage.append(.init(samples: .init(from: nextSample, through: vertices[firstVertex] - 1), vertices: nil))
            }
            result.sampleCoverage.append(.init(samples: .init(from: vertices[firstVertex], through: vertices[lastVertex]),
                vertices: .init(from: firstVertex, through: lastVertex)))
            nextSample = vertices[lastVertex] + 1
            firstVertex = lastVertex + 1
        }
        if nextSample < segments.count {
            result.sampleCoverage.append(.init(samples: .init(from: nextSample, through: segments.count - 1), vertices: nil))
        }
        result.warnings = [.trackingLost]
        return (map, raw, result)
    }

    @Test func secondBreakIsRejectedForSparseAndDenseVertices() throws {
        // Raw gaps: (1.4, 2.4) and (3.4, 4.4). Only the first is declared.
        // Both paths improperly connect the second gap in part 1.
        for (vertices, parts) in [([0, 1, 2, 4], [0, 0, 1, 1]),
                                  ([0, 1, 2, 3, 4], [0, 0, 1, 1, 1])] {
            let c = try example(segments: [1, 1, 2, 2, 3], vertices: vertices, parts: parts, gaps: [(1, 2)])
            #expect(throws: TrackValidationError.disconnectedPath) {
                try TrackDocumentValidator.result(TrackDocumentJSON.encode(c.result), raw: c.raw, floorPlan: c.map)
            }
        }
    }

    @Test func thirdBreakIsNotHiddenBehindTwoSeparatedParts() throws {
        // First two gaps are correctly separated; third gap (5.4, 6.4) is crossed.
        let c = try example(segments: [1, 1, 2, 2, 3, 3, 4],
            vertices: [0, 1, 2, 3, 4, 6], parts: [0, 0, 1, 1, 2, 2], gaps: [(1, 2), (3, 4)])
        #expect(throws: TrackValidationError.disconnectedPath) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(c.result), raw: c.raw, floorPlan: c.map)
        }
    }

    @Test func repeatedNilTrackingGapsCannotBeJoined() throws {
        let c = try example(segments: [1, 1, 1, 2, 2, 2, 3, 3], missing: [2, 5],
            vertices: [0, 1, 3, 6, 7], parts: [0, 0, 1, 1, 1], gaps: [(1, 3), (4, 6)])
        #expect(throws: TrackValidationError.disconnectedPath) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(c.result), raw: c.raw, floorPlan: c.map)
        }
    }

    @Test func correctlySeparatedPartsKeepBoundaryVerticesUnchanged() throws {
        // An edge may END at a positive gap's start or START at its end.
        // Reusing a part ID later does not join noncontiguous runs.
        let c = try example(segments: [1, 1, 2, 2, 3, 3, 4, 4],
            vertices: Array(0...7), parts: [0, 0, 1, 1, 0, 0, 2, 2], gaps: [(1, 2), (3, 4), (5, 6)])
        let bytes = try TrackDocumentJSON.encode(c.result)
        let checked = try TrackDocumentValidator.result(bytes, raw: c.raw, floorPlan: c.map)
        #expect(checked.bytes == bytes)
        #expect(checked.document == c.result)
    }

    @Test func zeroDurationBreakAfterPositiveGapIsStillRejected() throws {
        // The second break has zero duration but distinct source indices.
        // Reject its crossing by raw segment/coverage, not a time-only heuristic.
        let c = try example(segments: [1, 1, 2, 3, 3], times: [0, 1, 2, 2, 3],
            vertices: [0, 1, 2, 4], parts: [0, 0, 1, 1], gaps: [(1, 2)])
        #expect(throws: TrackValidationError.disconnectedPath) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(c.result), raw: c.raw, floorPlan: c.map)
        }
    }

    @Test func crossingResultCannotBePublishedOrSelected() async throws {
        let c = try example(segments: [1, 1, 2, 2, 3],
            vertices: [0, 1, 2, 4], parts: [0, 0, 1, 1], gaps: [(1, 2)])
        let identity = c.raw.document.identity
        let store = InMemoryTrackResultStore()
        try await store.seedSession(id: identity.sessionID, ownerUID: "instructor",
            members: [identity.memberID: "member"], map: c.map)
        try await store.confirmRaw(c.raw)
        let request = PublishTrackResultRequest(requestID: UUID(), identity: identity,
            resultJSON: try TrackDocumentJSON.encode(c.result))
        await #expect(throws: TrackValidationError.disconnectedPath) {
            try await store.client(authenticatedUID: "member").publishUsable(request)
        }
        let counts = await store.counts
        #expect(counts.ready == 0 && counts.pending == 0)
        #expect(try await store.client(authenticatedUID: "instructor").loadSelected(for: identity) == nil)
    }
}
