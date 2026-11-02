import SwiftUI
import UIKit
import OSLog

/// 기록 화면 이외에는 기기가 선택하는 세로·가로 방향을 허용한다.
final class MemberAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}

/// 가로 고정을 해제할 때도 scene의 기존 방향 대신 실제 기기 방향을 다시 반영한다.
struct MemberOrientation: UIViewControllerRepresentable {
    let usesLandscape: Bool

    func makeUIViewController(context: Context) -> OrientationController {
        OrientationController()
    }

    func updateUIViewController(_ controller: OrientationController, context: Context) {
        controller.update(usesLandscape: usesLandscape)
    }

    static func requestedMask(usesLandscape: Bool, device: UIDeviceOrientation,
                              current: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch device {
        case .portrait where !usesLandscape: return .portrait
        // UIDevice와 UIWindowScene의 가로 방향 명칭은 반대다.
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default:
            if usesLandscape { return current == .landscapeLeft ? .landscapeLeft : .landscapeRight }
            // 평평하게 놓였거나 방향을 아직 모르면 특정 방향으로 강제하지 않는다.
            return .allButUpsideDown
        }
    }

    final class OrientationController: UIViewController {
        private var usesLandscape = false
        private let logger = Logger(subsystem: "MemberApp", category: "Orientation")

        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            usesLandscape ? .landscape : .allButUpsideDown
        }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(self, selector: #selector(refreshOrientation),
                name: UIDevice.orientationDidChangeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(refreshOrientation),
                name: UIApplication.didBecomeActiveNotification, object: nil)
            applyOrientation()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            NotificationCenter.default.removeObserver(self)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }

        func update(usesLandscape: Bool) {
            let changed = self.usesLandscape != usesLandscape
            self.usesLandscape = usesLandscape
            MemberAppDelegate.orientationMask = supportedInterfaceOrientations
            if changed { applyOrientation() }
        }

        @objc private func refreshOrientation() { applyOrientation() }

        private func applyOrientation() {
            guard let scene = view.window?.windowScene else { return }
            MemberAppDelegate.orientationMask = supportedInterfaceOrientations
            var controller: UIViewController? = self
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.parent
            }
            let current = scene.interfaceOrientation
            let requested = MemberOrientation.requestedMask(
                usesLandscape: usesLandscape, device: UIDevice.current.orientation, current: current
            )
            let currentMask = UIInterfaceOrientationMask(rawValue: 1 << current.rawValue)
            guard !requested.contains(currentMask) else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: requested)) { [logger] error in
                logger.error("화면 방향 변경 실패: \(error.localizedDescription)")
            }
        }
    }
}
