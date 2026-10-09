import Foundation
import Testing
import CQBCore
import CQBFixtures

struct TrackFloatPrecisionTests {
    private func document(origin: Double, position: Double, relative: Double) throws -> RawTrackDocument {
        var raw = try TrackContractFixture.rawDocument(.normal)
        raw.originMeters = .init(x: origin, y: 0, z: -origin)
        raw.samples = [
            .init(time: 0, arTimestamp: 10, arPosition: [origin, 0, -origin],
                  relativeMeters: .init(x: 0, y: 0), trackingState: .normal, segment: 1),
            .init(time: 1, arTimestamp: 11, arPosition: [position, 0, -position],
                  relativeMeters: .init(x: relative, y: -relative), trackingState: .normal, segment: 1),
        ]
        return raw
    }

    @Test func pocFloatSubtractionKeepsOriginalBytesAndCoordinates() throws {
        let map = try contractTrackMap()
        let origin: Float = 0.1, position: Float = 40.1
        // Matches ARCaptureView: subtract Float values FIRST, then promote.
        let relative = Double(position - origin)
        #expect(abs(Double(position) - Double(origin) - relative) > 1e-6)
        let raw = try document(origin: Double(origin), position: Double(position), relative: relative)
        let bytes = try TrackDocumentJSON.encode(raw)
        let checked = try TrackDocumentValidator.raw(bytes, floorPlan: map)
        #expect(checked.document == raw)
        #expect(checked.bytes == bytes)
        #expect(checked.sha256 == FloorPlanJSON.sha256(bytes))
    }

    @Test func floatArithmeticAcrossSignsAndMagnitudesIsAccepted() throws {
        let map = try contractTrackMap()
        let origins: [Float] = [0, 0.1, -0.1, 1.2345, 5000, -5000]
        let positions: [Float] = [-1000.1, -40.1, -0.3, 0, 40.1, 1000.1, 100_000_000]
        // 42 deterministic cases; both X and Z use opposite signs.
        for origin in origins {
            for position in positions {
                let raw = try document(origin: Double(origin), position: Double(position),
                                       relative: Double(position - origin))
                let checked = try TrackDocumentValidator.raw(TrackDocumentJSON.encode(raw), floorPlan: map)
                #expect(checked.document == raw)
            }
        }
    }

    @Test func doubleArithmeticAndExistingAbsoluteToleranceRemainSupported() throws {
        let map = try contractTrackMap()
        let origin = 0.123456789, position = 40.123456789
        #expect(Double(Float(origin)) != origin && Double(Float(position)) != position)
        for offset in [0.0, 0.5e-6, -0.5e-6] {
            let raw = try document(origin: origin, position: position, relative: position - origin + offset)
            let checked = try TrackDocumentValidator.raw(TrackDocumentJSON.encode(raw), floorPlan: map)
            #expect(checked.document == raw)
        }
    }

    @Test func coordinateMismatchIsStillRejectedOnEitherAxis() throws {
        let map = try contractTrackMap()
        let origin: Float = 0.1, position: Float = 40.1
        let original = try document(origin: Double(origin), position: Double(position), relative: Double(position - origin))
        for offset in [-0.001, -0.00001, 0.00001, 0.001] {
            for axis in 0...1 {
                var raw = original
                if axis == 0 { raw.samples[1].relativeMeters!.x += offset }
                else { raw.samples[1].relativeMeters!.y += offset }
                #expect(throws: TrackValidationError.invalidRaw) {
                    try TrackDocumentValidator.raw(TrackDocumentJSON.encode(raw), floorPlan: map)
                }
            }
        }
    }

    @Test func largeCoordinatesDoNotPermitArbitraryValuesWithinOneFloatULP() throws {
        let map = try contractTrackMap()
        // A broad ULP tolerance at 1e8 could accept this unrelated 1m shift.
        // Only the two actual arithmetic paths, not all nearby values, are valid.
        let origin: Float = 0.1, position: Float = 100_000_000
        let raw = try document(origin: Double(origin), position: Double(position),
                               relative: Double(position - origin) + 1)
        #expect(throws: TrackValidationError.invalidRaw) {
            try TrackDocumentValidator.raw(TrackDocumentJSON.encode(raw), floorPlan: map)
        }
    }

    @Test func doubleOperandsAreNotSilentlyRoundedToFloat() throws {
        let map = try contractTrackMap()
        let origin = 0.1, position = 40.2 // Double literals, not promoted Float values.
        let relative = Double(Float(position) - Float(origin))
        #expect(abs(position - origin - relative) > 1e-6)
        let raw = try document(origin: origin, position: position, relative: relative)
        #expect(throws: TrackValidationError.invalidRaw) {
            try TrackDocumentValidator.raw(TrackDocumentJSON.encode(raw), floorPlan: map)
        }
    }

    @Test func overflowCannotCreateAnInfiniteTolerance() throws {
        let map = try contractTrackMap()
        let raw = try document(origin: -Double.greatestFiniteMagnitude,
                               position: Double.greatestFiniteMagnitude, relative: 0)
        #expect(throws: TrackValidationError.invalidRaw) {
            try TrackDocumentValidator.raw(TrackDocumentJSON.encode(raw), floorPlan: map)
        }
    }
}
