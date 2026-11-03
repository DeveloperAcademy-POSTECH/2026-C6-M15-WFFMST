import CQBCore
import XCTest
@testable import MemberApp

@MainActor
final class WorldMapPositionCalculatorTests: XCTestCase {
    func testRotationTranslationAndScalePreserveLivePositionAndHeading() throws {
        let map = try BundledTrainingMapLoader.load()
        let target = PositioningTestData.freePixel(map)
        for degrees in [0.0, 90, 180, 270] {
            for scale in [10.0, 40] {
                let a = degrees * .pi / 180
                let alignment = WorldMapAlignment(rotationDegrees: degrees, pixelsPerMeter: scale,
                    translation: ImagePoint(x: target.x - scale * (2 * cos(a) - 3 * sin(a)),
                                            y: target.y - scale * (2 * sin(a) + 3 * cos(a))),
                    rmsErrorMeters: 0, algorithmVersion: "test")
                let pose = ARPose(x: 2, y: 1.5, z: 3, forwardX: 1, forwardZ: 0)
                let position = try XCTUnwrap(WorldMapPositionCalculator.position(pose: pose, alignment: alignment, map: map))
                XCTAssertEqual(map.pixel(position.start).x, target.x, accuracy: 0.0001)
                XCTAssertEqual(map.pixel(position.start).y, target.y, accuracy: 0.0001)
                let dx = map.pixel(position.direction).x - target.x
                let dy = map.pixel(position.direction).y - target.y
                XCTAssertEqual(atan2(dy, dx), atan2(sin(a), cos(a)), accuracy: 0.0001)
                XCTAssertEqual(hypot(dx, dy), max(20, scale), accuracy: 0.0001)
            }
        }
    }

    func testInvalidPoseOutsideMapAndVerticalCameraCannotBecomeReady() throws {
        let map = try BundledTrainingMapLoader.load()
        let alignment = PositioningTestData.alignment(map)
        let invalid = [ARPose(x: .nan, y: 0, z: 0, forwardX: 1, forwardZ: 0),
                       ARPose(x: 1e6, y: 0, z: 0, forwardX: 1, forwardZ: 0),
                       ARPose(x: 0, y: 0, z: 0, forwardX: 0, forwardZ: 0)]
        for pose in invalid {
            XCTAssertNil(WorldMapPositionCalculator.position(pose: pose, alignment: alignment, map: map))
        }
    }

    func testBlockedStartIsRejected() throws {
        let map = try BundledTrainingMapLoader.load()
        let grid = map.navigation.grid
        let index = try XCTUnwrap(grid.blocked.firstIndex(of: 1))
        let alignment = WorldMapAlignment(rotationDegrees: 0, pixelsPerMeter: 20,
            translation: ImagePoint(x: (Double(index % grid.columns) + 0.5) * grid.cellSize,
                                    y: (Double(index / grid.columns) + 0.5) * grid.cellSize),
            rmsErrorMeters: 0, algorithmVersion: "test")
        XCTAssertNil(WorldMapPositionCalculator.position(pose: ARPose(x: 0, y: 0, z: 0, forwardX: 1, forwardZ: 0),
                                                         alignment: alignment, map: map))
    }
}
