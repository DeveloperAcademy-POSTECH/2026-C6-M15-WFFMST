import UIKit
import XCTest
@testable import MemberApp

@MainActor
final class MemberOrientationTests: XCTestCase {
    func testLeavingLandscapeScreenWhileDeviceIsPortraitRequestsPortrait() {
        XCTAssertEqual(MemberOrientation.requestedMask(usesLandscape: false, device: .portrait,
                                                       current: .landscapeRight), .portrait)
    }

    func testAutomaticScreensFollowBothPhysicalLandscapeDirections() {
        XCTAssertEqual(MemberOrientation.requestedMask(usesLandscape: false, device: .landscapeLeft,
                                                       current: .portrait), .landscapeRight)
        XCTAssertEqual(MemberOrientation.requestedMask(usesLandscape: false, device: .landscapeRight,
                                                       current: .portrait), .landscapeLeft)
    }

    func testTrainingScreenStaysLandscapeWhenDeviceIsHeldPortrait() {
        XCTAssertEqual(MemberOrientation.requestedMask(usesLandscape: true, device: .portrait,
                                                       current: .portrait), .landscapeRight)
        XCTAssertEqual(MemberOrientation.requestedMask(usesLandscape: true, device: .portrait,
                                                       current: .landscapeLeft), .landscapeLeft)
    }

    func testUnknownDeviceDirectionDoesNotForceAutomaticScreensToPortrait() {
        for orientation in [UIDeviceOrientation.unknown, .faceUp, .faceDown, .portraitUpsideDown] {
            XCTAssertEqual(MemberOrientation.requestedMask(usesLandscape: false, device: orientation,
                                                           current: .landscapeLeft), .allButUpsideDown)
        }
    }

    func testControllerAllowsRotationAgainAfterLeavingTraining() {
        let controller = MemberOrientation.OrientationController()
        controller.update(usesLandscape: true)
        XCTAssertEqual(controller.supportedInterfaceOrientations, .landscape)
        XCTAssertEqual(MemberAppDelegate.orientationMask, .landscape)
        controller.update(usesLandscape: false)
        XCTAssertEqual(controller.supportedInterfaceOrientations, .allButUpsideDown)
        XCTAssertEqual(MemberAppDelegate.orientationMask, .allButUpsideDown)
    }
}
