import SwiftUI
import UIKit
import XCTest
@testable import MemberApp

/// 카메라 입력과 분리해 실제 화면 View의 렌더링을 검토할 수 있도록 결과에 첨부한다.
@MainActor
final class MemberPositioningRenderingTests: XCTestCase {
    func testPositioningScreensRenderForLandscapeAndAccessibility() async throws {
        let states: [(String, MemberPositioningState, Bool, Bool)] = [
            ("scan", .relocalizing, false, false),
            ("fallback", .manualAvailable, false, false),
            ("ready", .automaticReady, true, false),
            ("demo", .relocalizing, false, true)
        ]
        for (name, state, ready, demo) in states {
            for accessible in [false, true] {
                let screen = TrainingRecordingContent(phase: .waiting, startedAt: nil, onFinish: {},
                    onReset: {}, allowsPositionReset: state == .manualAvailable || (state == .manualRequired && demo),
                    isCameraReady: ready, positioningState: state, isDemoMode: demo)
                    .frame(width: 874, height: 402)
                    .environment(\.dynamicTypeSize, accessible ? .accessibility3 : .large)
                    .background(Color.black)
                    .ignoresSafeArea()
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
                let controller = UIHostingController(rootView: screen)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: CGSize(width: 874, height: 402), format: format).image { _ in
                    controller.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: 874, height: 402), afterScreenUpdates: true)
                }
                window.isHidden = true
                let attachment = XCTAttachment(image: image)
                attachment.name = "issue150-\(name)-\(accessible ? "large-text" : "standard")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
