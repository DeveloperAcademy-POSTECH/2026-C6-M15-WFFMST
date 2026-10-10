import Foundation
import Testing
import CQBCore
import CQBFixtures

/// Initial camera preparation is not recovery from a previously valid position.
/// These cases preserve the capture samples rather than trimming or reindexing them.
struct TrackRawWarmupTests {
    private func raw(segments: [Int], missing: Set<Int>) throws -> RawTrackDocument {
        var source = try TrackContractFixture.rawDocument(.normal)
        source.samples = segments.indices.map { index in
            let x = Double(index) * 0.25
            let z = Double(index) * 0.125
            return .init(time: Double(index) * 0.1, arTimestamp: 100 + Double(index) * 0.1,
                arPosition: [source.originMeters.x + x, source.originMeters.y, source.originMeters.z + z],
                relativeMeters: missing.contains(index) ? nil : .init(x: x, y: z),
                trackingState: missing.contains(index) ? .initializing : .normal,
                segment: segments[index])
        }
        return source
    }

    private func expectPreserved(_ source: RawTrackDocument) throws {
        let map = try contractTrackMap()
        // A trailing newline proves validation keeps the supplied bytes, not a re-encoding.
        let bytes = try TrackDocumentJSON.encode(source) + Data("\n".utf8)
        let checked = try TrackDocumentValidator.raw(bytes, floorPlan: map)
        #expect(checked.document == source)
        #expect(checked.document.samples == source.samples)
        #expect(checked.document.startPose == source.startPose)
        #expect(checked.document.originMeters == source.originMeters)
        #expect(checked.document.recordingStartOffsetSeconds == source.recordingStartOffsetSeconds)
        #expect(checked.bytes == bytes)
        #expect(checked.sha256 == FloorPlanJSON.sha256(bytes))
        #expect(try checked.sha256 != FloorPlanJSON.sha256(TrackDocumentJSON.encode(source)))
    }

    @Test func firstPositionAfterOneInitialNilCanKeepSegment() throws {
        try expectPreserved(raw(segments: [0, 0, 0], missing: [0]))
    }

    @Test func firstPositionAfterSeveralInitialNilsCanKeepSegment() throws {
        try expectPreserved(raw(segments: [0, 0, 0, 0], missing: [0, 1, 2]))
    }

    @Test func firstPositionAfterInitialNilsCanAlsoIncreaseSegment() throws {
        try expectPreserved(raw(segments: [0, 0, 1, 1], missing: [0, 1]))
    }

    @Test func readyAtStartCaptureIsUnchanged() throws {
        // PoC begins with a normal sample in segment 1 after camera readiness.
        try expectPreserved(raw(segments: [1, 1, 1], missing: []))
    }

    @Test func realRecoveryStillRequiresSegmentIncrement() throws {
        let map = try contractTrackMap()
        for (segments, missing) in [([0, 0, 0], Set([1])),
                                     ([0, 0, 0, 0], Set([1, 2]))] {
            let source = try raw(segments: segments, missing: missing)
            #expect(throws: TrackValidationError.invalidRaw) {
                try TrackDocumentValidator.raw(TrackDocumentJSON.encode(source), floorPlan: map)
            }
        }
        try expectPreserved(raw(segments: [0, 0, 1], missing: [1]))
        try expectPreserved(raw(segments: [0, 0, 0, 1], missing: [1, 2]))
    }

    @Test func initialAllowanceDoesNotPermitLaterRecoveryWithoutIncrement() throws {
        let map = try contractTrackMap()
        let sameSegment = try raw(segments: [0, 0, 0, 0, 0], missing: [0, 2, 3])
        #expect(throws: TrackValidationError.invalidRaw) {
            try TrackDocumentValidator.raw(TrackDocumentJSON.encode(sameSegment), floorPlan: map)
        }
        try expectPreserved(raw(segments: [0, 0, 0, 0, 1], missing: [0, 2, 3]))
    }

    @Test func initialPreparationDoesNotPermitSegmentRegression() throws {
        let map = try contractTrackMap()
        for (segments, missing) in [([1, 0, 0], Set([0, 1])),
                                     ([1, 0], Set([0]))] {
            let source = try raw(segments: segments, missing: missing)
            #expect(throws: TrackValidationError.invalidRaw) {
                try TrackDocumentValidator.raw(TrackDocumentJSON.encode(source), floorPlan: map)
            }
        }
    }

    @Test func initialPreparationKeepsTimeStateAndOriginChecks() throws {
        let map = try contractTrackMap()
        let original = try raw(segments: [0, 0, 0], missing: [0])
        let changes: [(inout RawTrackDocument) -> Void] = [
            { $0.samples[0].trackingState = .normal },
            { $0.samples[1].trackingState = .initializing },
            { $0.samples[2].time = 0 },
            { $0.samples[1].arTimestamp = 99 },
            { $0.samples[1].relativeMeters = .init(x: 100, y: 100) },
            { $0.samples[1].arPosition = [1, 2] },
        ]
        for change in changes {
            var source = original
            change(&source)
            #expect(throws: TrackValidationError.invalidRaw) {
                try TrackDocumentValidator.raw(TrackDocumentJSON.encode(source), floorPlan: map)
            }
        }
    }

    @Test func allInitialNilSamplesRemainRawEvidenceNotFabricatedPositions() throws {
        // Raw validity alone does not claim a usable result; no position is invented.
        try expectPreserved(raw(segments: [0, 0, 0], missing: [0, 1, 2]))
    }
}
