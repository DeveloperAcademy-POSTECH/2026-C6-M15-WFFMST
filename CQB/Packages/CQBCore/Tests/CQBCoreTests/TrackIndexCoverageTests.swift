import Foundation
import Testing
import CQBCore
import CQBFixtures

// Deliberately hand-authored contract cases, not a V13 adapter or solver run.
private struct IndexedTrackCase {
    let map: ValidatedFloorPlan
    let raw: ValidatedRawTrack
    var result: TrackResultDocument

    init(times: [Double], segments: [Int]? = nil, missing: Set<Int> = [],
         runs: [TrackSampleCoverage], diagnostics: [TrackUnresolvedInterval],
         vertices: [TrackResultVertex]) throws {
        map = try contractTrackMap()
        var source = try TrackContractFixture.rawDocument(.normal)
        source.recordingStartOffsetSeconds = 2.5
        source.samples = times.enumerated().map { index, time in
            .init(time: time, arTimestamp: 100 + time,
                  arPosition: [source.originMeters.x + Double(index), source.originMeters.y, source.originMeters.z],
                  relativeMeters: missing.contains(index) ? nil : .init(x: Double(index), y: 0),
                  trackingState: missing.contains(index) ? .relocalizing : .normal,
                  segment: segments?[index] ?? 1)
        }
        raw = try TrackDocumentValidator.raw(TrackDocumentJSON.encode(source), floorPlan: map)
        result = TrackResultDocument(identity: source.identity, resultID: UUID(), floorPlan: source.floorPlan,
            sourceRawSHA256: raw.sha256,
            algorithm: .init(name: "hand-authored-index-regression", version: "1", settingsID: "manual"),
            status: diagnostics.isEmpty ? .done : .partial, vertices: vertices,
            sampleCoverage: runs, unresolvedIntervals: diagnostics, searchIncomplete: false, warnings: [])
    }

    func validate(_ value: TrackResultDocument? = nil) throws -> ValidatedTrackResult {
        try TrackDocumentValidator.result(TrackDocumentJSON.encode(value ?? result), raw: raw, floorPlan: map)
    }
}

private func indexedRun(_ from: Int, _ through: Int, _ firstVertex: Int?, _ lastVertex: Int? = nil) -> TrackSampleCoverage {
    .init(samples: .init(from: from, through: through),
          vertices: firstVertex.map { .init(from: $0, through: lastVertex ?? $0) })
}

private func indexedVertex(_ sample: Int?, time: Double, x: Double, part: Int = 0,
                           provenance: TrackPointProvenance = .correctedSample) -> TrackResultVertex {
    .init(t: time + 2.5, point: .init(x: x, y: 120), part: part, sampleIndex: sample, provenance: provenance)
}

private func indexedDiagnostic(_ from: Int, _ through: Int, start: Double, end: Double,
                               reason: TrackUnresolvedReason = .searchLimit,
                               sourceReason: String? = nil) -> TrackUnresolvedInterval {
    .init(from: start + 2.5, to: end + 2.5, bounds: .closed, reason: reason,
          samples: .init(from: from, through: through), sourceReason: sourceReason)
}

private func coincidentMissingCase(nilPosition: Bool = false) throws -> IndexedTrackCase {
    try IndexedTrackCase(times: [0, 1, 1], missing: nilPosition ? [2] : [],
        runs: [indexedRun(0, 1, 0, 1), indexedRun(2, 2, nil)],
        diagnostics: [indexedDiagnostic(2, 2, start: 1, end: 1,
            reason: nilPosition ? .trackingLost : .searchLimit, sourceReason: "원본 샘플 2만 미해결")],
        vertices: [indexedVertex(0, time: 0, x: 100), indexedVertex(1, time: 1, x: 110)])
}

private func continuousIndexCase() throws -> IndexedTrackCase {
    try IndexedTrackCase(times: [0, 1, 2], runs: [indexedRun(0, 2, 0, 2)], diagnostics: [],
        vertices: [indexedVertex(0, time: 0, x: 100), indexedVertex(1, time: 1, x: 110),
                   indexedVertex(2, time: 2, x: 120)])
}

private func coincidentResumeCase() throws -> IndexedTrackCase {
    try IndexedTrackCase(times: [0, 1, 1, 2], segments: [1, 1, 2, 2],
        runs: [indexedRun(0, 1, 0, 1), indexedRun(2, 3, 2, 3)],
        diagnostics: [indexedDiagnostic(2, 2, start: 1, end: 1, reason: .connectionUnverified,
            sourceReason: "추적 단절 이후 연결 미확인")],
        vertices: [indexedVertex(0, time: 0, x: 100), indexedVertex(1, time: 1, x: 110),
                   indexedVertex(2, time: 1, x: 120, part: 1), indexedVertex(3, time: 2, x: 130, part: 1)])
}

struct TrackIndexCoverageTests {
    @Test func initialUnknownPositionsStayMissingInResultRatherThanBecomingDone() throws {
        let c = try IndexedTrackCase(times: [0, 0, 1], missing: [0],
            runs: [indexedRun(0, 0, nil), indexedRun(1, 2, 0, 1)],
            diagnostics: [indexedDiagnostic(0, 0, start: 0, end: 0, reason: .trackingLost)],
            vertices: [indexedVertex(1, time: 0, x: 100), indexedVertex(2, time: 1, x: 110)])
        #expect(try c.validate().document == c.result)
        #expect(c.raw.document.samples.map(\.segment) == [1, 1, 1])
        var done = c.result; done.status = .done
        #expect(throws: TrackValidationError.invalidStatus) { try c.validate(done) }

        var allUnknown = try IndexedTrackCase(times: [0, 1], missing: [0, 1],
            runs: [indexedRun(0, 1, nil)],
            diagnostics: [indexedDiagnostic(0, 1, start: 0, end: 1, reason: .trackingLost)], vertices: [])
        allUnknown.result.status = .failed
        #expect(try allUnknown.validate().document.vertices.isEmpty)
        allUnknown.result.status = .partial
        #expect(throws: TrackValidationError.invalidStatus) { try allUnknown.validate() }
    }

    @Test func coincidentSolvedAndUnresolvedSamplesRemainDistinct() throws {
        let c = try coincidentMissingCase()
        let checked = try c.validate()
        #expect(checked.document == c.result)
        #expect(checked.document.vertices[1].t == checked.document.unresolvedIntervals[0].from)
        #expect(checked.document.vertices[1].sampleIndex == 1)
        #expect(checked.document.unresolvedIntervals[0].samples == .init(from: 2, through: 2))
        #expect(checked.document.sampleCoverage[1].vertices == nil)
        #expect(checked.document.status == .partial)
        #expect(c.raw.document.samples.map(\.time) == [0, 1, 1])
    }

    @Test func nilPositionAtSameTimeDoesNotInvalidateKnownEndpoint() throws {
        let c = try coincidentMissingCase(nilPosition: true)
        #expect(try c.validate().document == c.result)
        var inventedCoverage = c.result
        inventedCoverage.sampleCoverage = [indexedRun(0, 2, 0, 1)]
        #expect(throws: TrackValidationError.disconnectedPath) { try c.validate(inventedCoverage) }
    }

    @Test func indexedDiagnosticsSurviveCodecPublishRetryAndInstructorRead() async throws {
        var c = try coincidentMissingCase()
        c.result.warnings = [.headingAmbiguous, .searchIncomplete]
        c.result.searchIncomplete = true
        let store = InMemoryTrackResultStore()
        let identity = c.raw.document.identity
        try await store.seedSession(id: identity.sessionID, ownerUID: "instructor",
            members: [identity.memberID: "member"], map: c.map)
        try await store.confirmRaw(c.raw)
        let member = store.client(authenticatedUID: "member")
        let instructor = store.client(authenticatedUID: "instructor")
        let bytes = try TrackDocumentJSON.encode(c.result)
        let request = PublishTrackResultRequest(requestID: UUID(), identity: identity, resultJSON: bytes)
        await store.failOnce(at: .afterCommit)
        await #expect(throws: TrackRepositoryError.unavailable) { try await member.publishUsable(request) }
        let retried = try await member.publishUsable(request)
        let selected = try #require(try await instructor.loadSelected(for: identity))
        let loaded = try await instructor.load(resultID: c.result.resultID, for: identity)
        #expect(retried.bytes == bytes && selected.bytes == bytes && loaded.bytes == bytes)
        #expect(selected.document == c.result && loaded.document == c.result)
        #expect(selected.document.sourceRawSHA256 == c.raw.sha256)
        #expect(await store.counts.ready == 1)
    }

    @Test func coincidentSegmentBoundaryAllowsSplitPartsButNeverAnEdgeAcrossIt() throws {
        let c = try coincidentResumeCase()
        #expect(try c.validate().document == c.result)
        var joined = c.result
        joined.vertices = joined.vertices.map { vertex in var value = vertex; value.part = 0; return value }
        #expect(throws: TrackValidationError.disconnectedPath) { try c.validate(joined) }
        joined.sampleCoverage = [indexedRun(0, 3, 0, 3)]
        #expect(throws: TrackValidationError.disconnectedPath) { try c.validate(joined) }
    }

    @Test func resumeOnlyDiagnosticCanCoexistWithItsKnownVertex() throws {
        let c = try coincidentResumeCase()
        let checked = try c.validate().document
        let resume = checked.unresolvedIntervals[0]
        #expect(resume.samples == .init(from: 2, through: 2))
        #expect(checked.vertices[2].sampleIndex == 2 && checked.vertices[2].t == resume.from)
        #expect(checked.sampleCoverage.allSatisfy { $0.vertices != nil })
        #expect(checked.status == .partial)
        var falselyDone = c.result; falselyDone.status = .done
        #expect(throws: TrackValidationError.invalidStatus) { try c.validate(falselyDone) }
    }

    @Test func overlappingUnsortedDiagnosticsAndSolvedBoundaryPreserveProducerMeaning() throws {
        let diagnostics = [
            indexedDiagnostic(3, 4, start: 3, end: 4, sourceReason: "후반 탐색 실패"),
            indexedDiagnostic(1, 3, start: 1, end: 3, sourceReason: "해결된 경계 1을 포함한 탐색 제한"),
            indexedDiagnostic(2, 4, start: 2, end: 4, reason: .noCandidate, sourceReason: "후보 없음")
        ]
        let c = try IndexedTrackCase(times: [0, 1, 2, 3, 4],
            runs: [indexedRun(0, 1, 0, 1), indexedRun(2, 4, nil)], diagnostics: diagnostics,
            vertices: [indexedVertex(0, time: 0, x: 100), indexedVertex(1, time: 1, x: 110)])
        let checked = try c.validate().document
        #expect(checked.unresolvedIntervals == diagnostics)
        #expect(checked.vertices == c.result.vertices)
        #expect(checked.unresolvedIntervals[1].samples.from == checked.vertices[1].sampleIndex)
    }

    @Test func diagnosticBeforeTheBreakCannotJustifyALaterSplit() throws {
        let c = try coincidentResumeCase()
        var value = c.result
        value.unresolvedIntervals = [indexedDiagnostic(1, 1, start: 1, end: 1, reason: .connectionUnverified)]
        #expect(throws: TrackValidationError.invalidInterval) { try c.validate(value) }
        value.unresolvedIntervals = []
        #expect(throws: TrackValidationError.invalidInterval) { try c.validate(value) }
    }

    @Test func everyMissingIndexRequiresADiagnosticEvenIfItsTimeIsCovered() throws {
        let c = try coincidentMissingCase()
        var value = c.result
        value.unresolvedIntervals = []
        #expect(throws: TrackValidationError.invalidCoverage) { try c.validate(value) }
        value.unresolvedIntervals = [indexedDiagnostic(1, 1, start: 1, end: 1)]
        #expect(throws: TrackValidationError.invalidCoverage) { try c.validate(value) }
    }

    @Test func coverageMustPartitionAllRawAndOutputIndicesExactlyOnce() throws {
        let c = try continuousIndexCase()
        let invalid: [[TrackSampleCoverage]] = [
            [], [indexedRun(1, 2, 0, 2)], [indexedRun(0, 1, 0, 2)],
            [indexedRun(0, 3, 0, 2)], [indexedRun(-1, 2, 0, 2)], [indexedRun(0, -1, 0, 2)],
            [indexedRun(0, 1, 0, 1), indexedRun(1, 2, 2, 2)],
            [indexedRun(0, 0, 0), indexedRun(2, 2, 1, 2)],
            [indexedRun(0, 2, 1, 2)], [indexedRun(0, 2, 0, 3)],
            [indexedRun(0, 2, 0, -1)], [indexedRun(0, 2, -1, 2)],
            [indexedRun(Int.min, 2, 0, 2)], [indexedRun(0, Int.max, 0, 2)],
            [indexedRun(0, 2, Int.min, 2)], [indexedRun(0, 2, 0, Int.max)]
        ]
        for coverage in invalid {
            var value = c.result; value.sampleCoverage = coverage
            #expect(throws: TrackValidationError.invalidCoverage) { try c.validate(value) }
        }
        let split = try coincidentResumeCase()
        var duplicatedVertices = split.result
        duplicatedVertices.sampleCoverage[1].vertices = .init(from: 1, through: 3)
        #expect(throws: TrackValidationError.invalidCoverage) { try split.validate(duplicatedVertices) }
    }

    @Test func diagnosticIndicesAndDisplayTimesMustReferToExactSourceSamples() throws {
        let c = try coincidentMissingCase()
        let changes: [(inout TrackUnresolvedInterval) -> Void] = [
            { $0.samples.from = -1 }, { $0.samples.through = 3 },
            { $0.samples.from = Int.min }, { $0.samples.through = Int.max },
            { $0.samples = .init(from: 2, through: 1) },
            { $0.from -= 0.1 }, { $0.to += 0.1 },
            { $0.bounds = .open }, { $0.bounds = .startOpen }, { $0.bounds = .endOpen }
        ]
        for change in changes {
            var value = c.result; change(&value.unresolvedIntervals[0])
            #expect(throws: TrackValidationError.invalidInterval) { try c.validate(value) }
        }
    }

    @Test func vertexReferencesStayInsideTheirCoverageAndCorrectedTimesMatchSource() throws {
        let c = try continuousIndexCase()
        let changes: [(inout TrackResultVertex) -> Void] = [
            { $0.sampleIndex = -1 }, { $0.sampleIndex = 3 },
            { $0.sampleIndex = nil }, { $0.t += 0.1 }, { $0.part = -1 }
        ]
        for change in changes {
            var value = c.result; change(&value.vertices[1])
            #expect(throws: TrackValidationError.invalidResult) { try c.validate(value) }
        }
        let split = try coincidentResumeCase()
        var outsideRun = split.result
        outsideRun.vertices[1].sampleIndex = 2 // Same timestamp is insufficient; wrong source run.
        #expect(throws: TrackValidationError.invalidResult) { try split.validate(outsideRun) }
        var mixedParts = c.result; mixedParts.vertices[1].part = 1
        #expect(throws: TrackValidationError.invalidCoverage) { try c.validate(mixedParts) }
        var truncated = c.result; truncated.vertices[0].t += 0.1
        #expect(throws: TrackValidationError.invalidCoverage) { try c.validate(truncated) }
    }

    @Test func sparseAndGeneratedVerticesNeedNotCountOrUniquelyIdentifySamples() throws {
        let c = try IndexedTrackCase(times: [0, 1, 2, 3], runs: [indexedRun(0, 3, 0, 3)], diagnostics: [],
            vertices: [indexedVertex(0, time: 0, x: 100),
                       indexedVertex(nil, time: 1, x: 110, provenance: .generated),
                       indexedVertex(3, time: 2, x: 120, provenance: .generated),
                       indexedVertex(3, time: 3, x: 130)])
        #expect(try c.validate().document == c.result)
        var sparse = c.result
        sparse.vertices = [sparse.vertices[0], sparse.vertices[3]]
        sparse.sampleCoverage = [indexedRun(0, 3, 0, 1)]
        #expect(try c.validate(sparse).document == sparse)
        var guessedProvenance = c.result; guessedProvenance.vertices[2].provenance = .correctedSample
        #expect(throws: TrackValidationError.invalidResult) { try c.validate(guessedProvenance) }
    }

    @Test func correctedEndpointsCannotClaimNeighboringSamplesWithIdenticalTimes() throws {
        // The last corrected point explicitly belongs to sample 1, not sample 2.
        let end = try IndexedTrackCase(times: [0, 1, 1], runs: [indexedRun(0, 2, 0, 1)], diagnostics: [],
            vertices: [indexedVertex(0, time: 0, x: 100), indexedVertex(1, time: 1, x: 110)])
        #expect(throws: TrackValidationError.invalidCoverage) { try end.validate() }

        // The same restriction applies to the first corrected point: equal time
        // cannot silently expand a run backwards from sample 1 to sample 0.
        let start = try IndexedTrackCase(times: [0, 0, 1], runs: [indexedRun(0, 2, 0, 1)], diagnostics: [],
            vertices: [indexedVertex(1, time: 0, x: 100), indexedVertex(2, time: 1, x: 110)])
        #expect(throws: TrackValidationError.invalidCoverage) { try start.validate() }
    }

    @Test func generatedAndUnspecifiedEndpointsStillUseExplicitProducerCoverage() throws {
        let c = try IndexedTrackCase(times: [0, 1, 1], runs: [indexedRun(0, 2, 0, 2)], diagnostics: [],
            vertices: [indexedVertex(nil, time: 0, x: 100, provenance: .generated),
                       indexedVertex(1, time: 1, x: 110, provenance: .unspecified),
                       indexedVertex(1, time: 1, x: 120, provenance: .generated)])
        #expect(try c.validate().document == c.result)
        var unspecified = c.result
        unspecified.vertices[0].provenance = .unspecified
        unspecified.vertices[2].provenance = .unspecified
        #expect(try c.validate(unspecified).document == unspecified)
        // A generated endpoint may reference the same target sample as other
        // generated points. It is not proof of one corrected vertex per sample.
        var repeated = c.result
        repeated.vertices[0].sampleIndex = 1
        #expect(try c.validate(repeated).document == repeated)
    }

    @Test func oldTimeOnlyJSONCannotSilentlyAcquireIndexCoverage() throws {
        let c = try coincidentMissingCase()
        let original = try #require(JSONSerialization.jsonObject(with: TrackDocumentJSON.encode(c.result)) as? [String: Any])
        var missingCoverage = original
        missingCoverage.removeValue(forKey: "sampleCoverage")
        var missingDiagnosticIndices = original
        var intervals = try #require(missingDiagnosticIndices["unresolvedIntervals"] as? [[String: Any]])
        intervals[0].removeValue(forKey: "samples")
        missingDiagnosticIndices["unresolvedIntervals"] = intervals
        for json in [missingCoverage, missingDiagnosticIndices] {
            let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            #expect(throws: TrackValidationError.invalidJSON) {
                try TrackDocumentValidator.result(bytes, raw: c.raw, floorPlan: c.map)
            }
        }
    }
}
