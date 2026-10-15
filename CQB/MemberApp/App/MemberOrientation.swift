import SwiftUI
import UIKit
import OSLog

/// MemberApp은 단일 iPhone 창을 사용한다. 초기 화면은 세로 방향이다.
final class MemberAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}

/// 현재 화면이 속한 scene에만 방향 변경을 요청한다.
struct MemberOrientation: UIViewControllerRepresentable {
    let usesLandscape: Bool

    func makeUIViewController(context: Context) -> OrientationController {
        OrientationController()
    }

    func updateUIViewController(_ controller: OrientationController, context: Context) {
        controller.update(mask: usesLandscape ? .landscape : .portrait)
    }

    final class OrientationController: UIViewController {
        private var mask: UIInterfaceOrientationMask = .portrait
        private let logger = Logger(subsystem: "MemberApp", category: "Orientation")

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyOrientation()
        }

        func update(mask: UIInterfaceOrientationMask) {
            let changed = self.mask != mask
            self.mask = mask
            MemberAppDelegate.orientationMask = mask
            if changed { applyOrientation() }
        }

        private func applyOrientation() {
            guard let scene = view.window?.windowScene else { return }
            MemberAppDelegate.orientationMask = mask
            var controller: UIViewController? = self
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.parent
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [logger] error in
                logger.error("화면 방향 변경 실패: \(error.localizedDescription)")
            }
        }
    }
}
