import Foundation
import XCTest
@testable import MemberApp

final class RouteCorrectionTests: XCTestCase {
    func testWorldMapRegistrationIncludesZeroAndCardinalOffsetsOnly() {
        let candidates = RouteRegistration.worldMapCandidates
        XCTAssertEqual(candidates.count, 153)
        XCTAssertEqual(Set(candidates).count, 153)
        XCTAssertEqual(Set(candidates.map(\.offsetDegrees)).sorted(),
                       [-30, -26, -22, -18, -14, -10, -6, -2, 0, 2, 6, 10, 14, 18, 22, 26, 30])
        for candidate in candidates {
            XCTAssertTrue(candidate.coherentOnly)
            XCTAssertTrue(candidate.translationXMeters == 0 || candidate.translationYMeters == 0)
            XCTAssertLessThanOrEqual(sqrt(candidate.squaredTranslation), 1)
        }
        let registration = RouteRegistration(offsetDegrees: 30, translationXMeters: 0.5, translationYMeters: -1)
        let anchor = registration.anchor(from: MapPoint(x: 100, y: 200), pixelsPerMeter: 24)
        // Translation is applied in image axes after rotation, not rotated a second time.
        XCTAssertEqual(anchor.x, 112)
        XCTAssertEqual(anchor.y, 176)
    }

    func testShiftedRegistrationCanCompleteCorridorWithoutMovingRawAnchor() throws {
        // Only y=50 is connected. Original anchor y=40 is free but isolated.
        let map = corridorMap()
        let input = straightInput()
        let anchor = MapPoint(x: 20, y: 40)
        let result = try XCTUnwrap(match(input, anchor: anchor, map: map, mode: .worldMap))
        let chosen = try XCTUnwrap(result.chosen)
        let registration = try XCTUnwrap(chosen.initialHeading?.registration)
        XCTAssertEqual(chosen.initialHeading?.distanceCoverage, 1)
        XCTAssertEqual(registration.translationXMeters, 0)
        XCTAssertEqual(registration.translationYMeters, 1)
        XCTAssertTrue(registration.coherentOnly)
        XCTAssertEqual(chosen.vertices.first?.point.y, 50)
        XCTAssertEqual(result.anchor.y, 50)
        XCTAssertEqual(anchor.y, 40)
        XCTAssertTrue(chosen.unresolved.isEmpty)
        XCTAssertEqual(chosen.vertices.last?.sampleIndex, input.count - 1)
        for candidate in result.candidates {
            XCTAssertTrue(map.grid.isFree(try XCTUnwrap(candidate.vertices.first).point))
            for (a, b) in zip(candidate.vertices, candidate.vertices.dropFirst()) where a.part == b.part {
                XCTAssertTrue(map.grid.canTravel(a.point, b.point))
            }
        }

        let manual = try XCTUnwrap(match(input, anchor: anchor, map: map, mode: .manual))
        XCTAssertEqual(manual.chosen?.vertices.first?.point.y, 40)
        XCTAssertNil(manual.chosen?.initialHeading?.registration)
        XCTAssertLessThan(manual.chosen?.initialHeading?.distanceCoverage ?? 0, 1)
    }

    func testManualDefaultPreservesOriginalMatcherAndFixedAnchor() throws {
        let map = freeMap()
        let input = straightInput()
        let anchor = MapPoint(x: 20, y: 40)
        let original = try XCTUnwrap(InitialHeadingMatcher.match(input: input, anchor: anchor,
            pixelsPerMeter: 10, rotationDegrees: 0, map: map, mapHash: "test", recordingID: "test",
            preserveExcursions: true, improvedExcursions: true))
        let manual = try XCTUnwrap(match(input, anchor: anchor, map: map, mode: .manual))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(original.candidates), try encoder.encode(manual.candidates))
        XCTAssertEqual(manual.anchor.x, anchor.x)
        XCTAssertEqual(manual.anchor.y, anchor.y)
    }

    func testRuntimeRegistrationDoesNotChangeDiagnosticJSONShape() throws {
        var fit = InitialHeadingFit(rotationDegrees: 6, offsetDegrees: 6, distanceCoverage: 1,
            coveredLengthRatio: 1, localPositionChangeMeters: 0.1, objective: 0.02)
        fit.registration = RouteRegistration(offsetDegrees: 6, translationXMeters: 0.5, coherentOnly: true)
        let bytes = try JSONEncoder().encode(fit)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["rotationDegrees", "offsetDegrees", "distanceCoverage",
                                             "coveredLengthRatio", "localPositionChangeMeters", "objective"]))
        let restored = try JSONDecoder().decode(InitialHeadingFit.self, from: bytes)
        XCTAssertNil(restored.registration)
        XCTAssertEqual(restored.offsetDegrees, 6)
    }

    private func match(_ input: [MatchInput], anchor: MapPoint, map: MatchNavigationMap,
                       mode: RouteCorrectionMode) -> MapMatchResult? {
        InitialHeadingMatcher.match(input: input, anchor: anchor, pixelsPerMeter: 10, rotationDegrees: 0,
            map: map, mapHash: "test", recordingID: "test", preserveExcursions: true,
            improvedExcursions: true, mode: mode)
    }

    private func straightInput() -> [MatchInput] {
        (0...40).map { MatchInput(meters: MapPoint(x: Double($0) * 0.2, y: 0), time: Double($0), segment: 0) }
    }

    private func freeMap() -> MatchNavigationMap {
        MatchNavigationMap(grid: RouteObstacleGrid(columns: 160, rows: 100, cellSize: 1,
            blocked: Array(repeating: 0, count: 160 * 100), minX: 0, maxX: 159, minY: 0, maxY: 99))
    }

    private func corridorMap() -> MatchNavigationMap {
        var mask = Array(repeating: UInt8(1), count: 160 * 100)
        for y in 48...54 { for x in 15...140 { mask[y * 160 + x] = 0 } }
        mask[40 * 160 + 20] = 0
        return MatchNavigationMap(grid: RouteObstacleGrid(columns: 160, rows: 100, cellSize: 1,
            blocked: mask, minX: 0, maxX: 159, minY: 0, maxY: 99))
    }
}
