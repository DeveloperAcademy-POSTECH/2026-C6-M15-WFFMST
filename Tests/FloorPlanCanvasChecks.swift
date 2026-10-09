import Foundation
import UIKit
import PencilKit

// Simulator-only UIKit harness. Programmatic zoom/delegate events do not replace physical Pencil/pinch QA.
@main
@MainActor
final class FloorPlanCanvasChecks: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Canvas Checks", sessionRole: session.role)
        configuration.delegateClass = FloorPlanCanvasChecksScene.self
        return configuration
    }
    func start(in host: UIView) {
        Task {
            let report: String
            do {
                try await run(in: host)
                report = "PASS: UIKit zoom/pan coordinates, PencilKit ordered strokes, late path, image replacement, teardown"
            } catch {
                report = "FAIL: \(error)"
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? report.write(to: documents.appendingPathComponent("canvas-check-result.txt"), atomically: true, encoding: .utf8)
            print(report)
        }
    }

    func run(in host: UIView) async throws {
        let view = LocalFloorPlanCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        host.addSubview(view)
        let image = makeImage(size: CGSize(width: 1_200, height: 800))
        update(view, image: image, tool: .block)
        view.layoutIfNeeded()
        guard let scroll = view.subviews.compactMap({ $0 as? UIScrollView }).first,
              let content = view.viewForZooming(in: scroll),
              let canvas = content.subviews.compactMap({ $0 as? PKCanvasView }).first else {
            throw Failure(message: "Canvas UIKit hierarchy missing")
        }
        try check(abs(scroll.zoomScale - 0.5) < 0.0001, "initial image fit must be 0.5")
        let imagePoint = CGPoint(x: 420, y: 280)
        let fittedScreen = content.convert(imagePoint, to: view)
        let fittedBack = canvas.convert(fittedScreen, from: view)
        try same(fittedBack, imagePoint, "initial image coordinates")
        scroll.setZoomScale(1.5, animated: false)
        scroll.setContentOffset(CGPoint(x: 320, y: 170), animated: false)
        view.layoutIfNeeded()
        let movedScreen = content.convert(imagePoint, to: view)
        try check(hypot(movedScreen.x - fittedScreen.x, movedScreen.y - fittedScreen.y) > 10,
                  "zoom/offset must really change display position")
        try same(canvas.convert(movedScreen, from: view), imagePoint, "same image point after zoom and pan")
        try check(scroll.panGestureRecognizer.minimumNumberOfTouches == 2, "drawing uses two-finger pan")

        var strokes: [LocalEditStroke] = []
        var editing: [Bool] = []
        view.onStroke = { strokes.append($0) }
        view.onEditingChanged = { editing.append($0) }
        view.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = drawing(at: imagePoint, transform: CGAffineTransform(translationX: 12, y: 8))
        view.canvasViewDidEndUsingTool(canvas)
        // A new stroke may start before the first end callback has executed.
        update(view, image: image, tool: .open)
        view.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = drawing(at: CGPoint(x: 600, y: 400))
        view.canvasViewDidEndUsingTool(canvas)
        try await drain()
        try check(strokes.count == 2 && strokes[0].mode == .block && strokes[1].mode == .open,
                  "fast block/open strokes must preserve order and mode")
        try check(abs(strokes[0].points[0].x - 0.36) < 1e-6 && abs(strokes[0].points[0].y - 0.36) < 1e-6,
                  "stroke transform and image normalization must be applied independently of zoom")
        try check(strokes.allSatisfy { $0.normalizedDiameter == 0.02 }, "fixed diameter ignores Pencil pressure")
        try check(canvas.drawing.strokes.isEmpty && editing.last == false, "completed PKDrawing must clear")

        view.canvasViewDidBeginUsingTool(canvas)
        view.canvasViewDidEndUsingTool(canvas)
        try await drain()
        canvas.drawing = drawing(at: CGPoint(x: 240, y: 160))
        view.canvasViewDrawingDidChange(canvas)
        try await drain()
        try check(strokes.count == 3, "late final drawing after DidEnd must commit exactly once")

        // Replacing a source while a completion is queued must drop that old stroke.
        view.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = drawing(at: CGPoint(x: 100, y: 100))
        view.canvasViewDidEndUsingTool(canvas)
        let replacement = makeImage(size: CGSize(width: 400, height: 1_000))
        update(view, image: replacement, tool: .move)
        view.layoutIfNeeded()
        try await drain()
        try check(strokes.count == 3 && canvas.drawing.strokes.isEmpty, "source replacement must discard pending old strokes")
        try check(content.bounds.size == CGSize(width: 400, height: 1_000) && canvas.bounds.size == content.bounds.size,
                  "replacement while zoomed must reset image/canvas bounds")
        try check(abs(scroll.zoomScale - 0.4) < 0.0001, "replacement must fit new image")
        try check(scroll.panGestureRecognizer.minimumNumberOfTouches == 1, "move mode uses one-finger pan")
        try same(canvas.convert(content.convert(CGPoint(x: 100, y: 500), to: view), from: view),
                 CGPoint(x: 100, y: 500), "replacement coordinate transform")
        try check(editing.last == false, "replacement must end edit state")

        update(view, image: replacement, tool: .block)
        view.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = drawing(at: CGPoint(x: 50, y: 100))
        view.canvasViewDidEndUsingTool(canvas)
        view.tearDown()
        try await drain()
        try check(strokes.count == 3, "teardown cancels queued callback")
        try check(view.onStroke == nil && view.onPoint == nil && view.onEditingChanged == nil,
                  "teardown releases callbacks")
        try check(canvas.delegate == nil && scroll.delegate == nil, "teardown releases delegates")
        view.removeFromSuperview()
    }

    func update(_ view: LocalFloorPlanCanvasView, image: UIImage, tool: LocalCanvasTool) {
        view.update(image: image, mask: nil, tool: tool, normalizedDiameter: 0.02,
                    outline: [], scaleA: nil, scaleB: nil, scaleLabel: nil)
    }
    func makeImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
    func drawing(at point: CGPoint, transform: CGAffineTransform = .identity) -> PKDrawing {
        let points = [point, CGPoint(x: point.x + 20, y: point.y + 10)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                          size: CGSize(width: 10, height: 10), opacity: 1,
                          force: index == 0 ? 0.1 : 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(ink: PKInk(.monoline, color: .black), path: path, transform: transform, mask: nil)
        return PKDrawing(strokes: [stroke])
    }
    func drain() async throws { try await Task.sleep(for: .milliseconds(80)) }
    func same(_ a: CGPoint, _ b: CGPoint, _ message: String) throws {
        try check(hypot(a.x - b.x, a.y - b.y) < 0.001, message)
    }
    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}

@MainActor
final class FloorPlanCanvasChecksScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene,
              let app = UIApplication.shared.delegate as? FloorPlanCanvasChecks else { return }
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        app.start(in: controller.view)
    }
}
