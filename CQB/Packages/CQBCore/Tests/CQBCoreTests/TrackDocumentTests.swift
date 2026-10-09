import Foundation
import Testing
import CQBCore
import CQBFixtures
import CQBImageIO

func contractTrackMap() throws -> ValidatedFloorPlan {
    try FloorPlanValidator(imageValidator: PNGFloorPlanImageValidator()).validate(
        files: FloorPlanFiles(imagePNG: NormalFloorPlanFixture.data(for: .image),
            navigationMapJSON: NormalFloorPlanFixture.data(for: .manifest),
            resolvedMask: NormalFloorPlanFixture.data(for: .mask)),
        reference: JSONDecoder().decode(FloorPlanReference.self, from: NormalFloorPlanFixture.data(for: .reference)))
}

struct TrackDocumentTests {
    @Test func headingAmbiguityPreservesGeometryAndDoesNotDowngradeStatus() throws {
        let map = try contractTrackMap()
        for example in [TrackContractFixture.Case.normal, .trackingGap] {
            let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(example), floorPlan: map)
            let original = try TrackContractFixture.resultDocument(example)
            var result = original
            result.warnings.append(.headingAmbiguous)
            let checked = try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
            #expect(checked.document == result)
            #expect(checked.document.vertices == original.vertices)
            #expect(checked.document.status == original.status)
            #expect(checked.document.unresolvedIntervals == original.unresolvedIntervals)
        }
    }

    @Test func unknownResultWarningIsRejectedRatherThanSilentlyDropped() throws {
        let map = try contractTrackMap()
        let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(.normal), floorPlan: map)
        var result = try TrackContractFixture.resultDocument(.normal)
        result.warnings = [.headingAmbiguous]
        let json = String(decoding: try TrackDocumentJSON.encode(result), as: UTF8.self)
        let bytes = Data(json.replacingOccurrences(of: "headingAmbiguous", with: "futureWarning").utf8)
        #expect(throws: TrackValidationError.invalidJSON) {
            try TrackDocumentValidator.result(bytes, raw: raw, floorPlan: map)
        }
    }

    @Test func fourExamplesRoundTripThroughCommonValidator() throws {
        let map = try contractTrackMap()
        for example in TrackContractFixture.Case.allCases {
            let bytes = try TrackContractFixture.rawJSON(example)
            let raw = try TrackDocumentValidator.raw(bytes, floorPlan: map)
            #expect(raw.bytes == bytes && raw.sha256 == FloorPlanJSON.sha256(bytes))
            #expect(try raw.document == TrackContractFixture.rawDocument(example))
            let resultBytes = try TrackContractFixture.resultJSON(example)
            let result = try TrackDocumentValidator.result(resultBytes, raw: raw, floorPlan: map)
            #expect(result.bytes == resultBytes)
            #expect(try result.document == TrackContractFixture.resultDocument(example))
            #expect(result.document.algorithm.name == "hand-authored-not-v13-execution")
        }
    }

    @Test func exactRawBytesNotSemanticReencodingDetermineHash() throws {
        let map = try contractTrackMap()
        let bytes = try TrackContractFixture.rawJSON(.normal) + Data("\n".utf8)
        let raw = try TrackDocumentValidator.raw(bytes, floorPlan: map)
        #expect(throws: TrackValidationError.rawHashMismatch) {
            try TrackDocumentValidator.result(TrackContractFixture.resultJSON(.normal), raw: raw, floorPlan: map)
        }
        var result = try TrackContractFixture.resultDocument(.normal)
        result.sourceRawSHA256 = raw.sha256
        _ = try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
    }

    @Test func unsupportedVersionMalformedJSONAndUnknownEnumAreRejected() throws {
        let map = try contractTrackMap()
        var raw = try TrackContractFixture.rawDocument(.normal)
        raw.schemaVersion = 99
        #expect(throws: TrackValidationError.unsupportedSchema(99)) {
            try TrackDocumentValidator.raw(TrackDocumentJSON.encode(raw), floorPlan: map)
        }
        for bytes in [Data(), Data("{".utf8), Data("{\"schemaVersion\":1}".utf8)] {
            #expect(throws: TrackValidationError.invalidJSON) { try TrackDocumentValidator.raw(bytes, floorPlan: map) }
        }
        let source = String(decoding: try TrackContractFixture.rawJSON(.normal), as: UTF8.self)
        #expect(throws: TrackValidationError.invalidJSON) {
            try TrackDocumentValidator.raw(Data(source.replacingOccurrences(of: "\"normal\"", with: "\"new-state\"").utf8), floorPlan: map)
        }
    }

    @Test func rawMustPreserveOriginTrackingAndSegmentMeaning() throws {
        let map = try contractTrackMap()
        let original = try TrackContractFixture.rawDocument(.trackingGap)
        let changes: [(inout RawTrackDocument) -> Void] = [
            { $0.samples[4].segment = 1 }, { $0.samples[2].relativeMeters = .init(x: 1, y: 0) },
            { $0.samples[0].relativeMeters = nil }, { $0.samples[1].arPosition = [1, 2] },
            { $0.samples[1].relativeMeters = .init(x: 100, y: 0) },
            { $0.samples[2].time = -1 }, { $0.samples[2].time = 0 },
            { $0.samples[2].arTimestamp = 1 }, { $0.samples = [] },
        ]
        for change in changes {
            var value = original; change(&value)
            #expect(throws: TrackValidationError.invalidRaw) {
                try TrackDocumentValidator.raw(TrackDocumentJSON.encode(value), floorPlan: map)
            }
        }
    }

    @Test func resultRejectsWrongIdentityMapAndSource() throws {
        let map = try contractTrackMap()
        let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(.normal), floorPlan: map)
        var value = try TrackContractFixture.resultDocument(.normal)
        value.identity.recordingID = UUID()
        #expect(throws: TrackValidationError.referenceMismatch) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(value), raw: raw, floorPlan: map)
        }
        value = try TrackContractFixture.resultDocument(.normal)
        value.floorPlan = .init(floorPlanID: map.reference.floorPlanID, revisionID: UUID(), navigationSHA256: map.reference.navigationSHA256)
        #expect(throws: TrackValidationError.referenceMismatch) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(value), raw: raw, floorPlan: map)
        }
    }

    @Test func trackingGapCannotBeHiddenByCompletionOrConnectingParts() throws {
        let map = try contractTrackMap()
        let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(.trackingGap), floorPlan: map)
        var result = try TrackContractFixture.resultDocument(.trackingGap)
        result.status = .done
        #expect(throws: TrackValidationError.invalidStatus) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        }
        result.status = .partial
        for i in result.vertices.indices { result.vertices[i].part = 0 }
        #expect(throws: TrackValidationError.disconnectedPath) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        }
        result.unresolvedIntervals = []
        #expect(throws: TrackValidationError.disconnectedPath) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        }
    }

    @Test func sparseVerticesAndGeneratedPointsDoNotRequireOneVertexPerSample() throws {
        let map = try contractTrackMap()
        let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(.normal), floorPlan: map)
        var result = try TrackContractFixture.resultDocument(.normal)
        result.vertices.remove(at: 1)
        _ = try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        result.vertices.insert(.init(t: 1, point: .init(x: 115, y: 125), part: 0, sampleIndex: nil, provenance: .generated), at: 1)
        _ = try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        result.vertices[1].provenance = .correctedSample
        #expect(throws: TrackValidationError.invalidResult) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        }
    }

    @Test func badCoordinatesIndicesTimesAndStatusAreRejected() throws {
        let map = try contractTrackMap()
        let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(.normal), floorPlan: map)
        let changes: [(inout TrackResultDocument) -> Void] = [
            { $0.vertices[1].point = .init(x: 220, y: 120) },
            { $0.vertices[1].point = .init(x: 1000, y: 120) },
            { $0.vertices[1].sampleIndex = 500 }, { $0.vertices[1].part = -1 },
            { $0.vertices[1].t = 50 }, { $0.vertices[1].t = 0 },
            { $0.algorithm.settingsID = " " },
        ]
        for change in changes {
            var result = try TrackContractFixture.resultDocument(.normal); change(&result)
            #expect(throws: TrackValidationError.invalidResult) {
                try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
            }
        }
        var result = try TrackContractFixture.resultDocument(.normal)
        result.status = .failed
        #expect(throws: TrackValidationError.invalidStatus) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        }
    }

    @Test func missingCoverageAndOverlappingIntervalsAreRejected() throws {
        let map = try contractTrackMap()
        let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(.searchLimit), floorPlan: map)
        var result = try TrackContractFixture.resultDocument(.searchLimit)
        result.unresolvedIntervals[0].to = 2.4
        #expect(throws: TrackValidationError.invalidStatus) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        }
        result.unresolvedIntervals.append(result.unresolvedIntervals[0])
        #expect(throws: TrackValidationError.invalidInterval) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        }
    }

    @Test func diagnosticsDoNotFabricateAccuracyOrFailureReason() throws {
        let map = try contractTrackMap()
        let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(.insufficientMovement), floorPlan: map)
        var result = try TrackContractFixture.resultDocument(.insufficientMovement)
        result.failureReason = nil
        let checked = try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        #expect(checked.document.failureReason == nil && checked.document.vertices.isEmpty)
    }

    @Test func disconnectedPartsNeedAnExplicitTimeGap() throws {
        let map = try contractTrackMap()
        let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(.normal), floorPlan: map)
        var result = try TrackContractFixture.resultDocument(.normal)
        result.vertices[2].part = 1
        #expect(throws: TrackValidationError.invalidInterval) {
            try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
        }
    }

    @Test func cancellationIsNotReclassifiedAsMalformedJSON() async throws {
        let map = try contractTrackMap()
        let bytes = try TrackContractFixture.rawJSON(.normal)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TrackDocumentValidator.raw(bytes, floorPlan: map)
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {} catch { Issue.record("Unexpected: \(error)") }
    }
}
