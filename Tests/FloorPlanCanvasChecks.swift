import Foundation
import UIKit
import PencilKit
import SwiftUI

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
                try await checkEditorLayout(in: host)
                try await checkEditingButtonAppearance(in: host)
                report = "PASS: UIKit zoom/pan, strokes, replacement, importer focus, layers, stable editor viewport and button appearance"
            } catch {
                report = "FAIL: \(error)"
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? report.write(to: documents.appendingPathComponent("canvas-check-result.txt"), atomically: true, encoding: .utf8)
            print(report)
        }
    }

    func checkEditingButtonAppearance(in host: UIView) async throws {
        func snapshot(enabled: Bool, preserve: Bool) async throws -> Data? {
            let controller = UIHostingController(rootView:
                ActionButton("막기") {}
                    .buttonStyle(FloorPlanEditingButtonStyle(preservesEnabledAppearance: preserve))
                    .disabled(!enabled).frame(width: 240, height: 60).background(.white))
            controller.overrideUserInterfaceStyle = .light
            controller.view.frame = CGRect(x: 0, y: 0, width: 240, height: 60)
            host.addSubview(controller.view)
            defer { controller.view.removeFromSuperview() }
            try await drain()
            controller.view.layoutIfNeeded()
            return UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }.pngData()
        }
        let enabled = try await snapshot(enabled: true, preserve: false)
        let transientLock = try await snapshot(enabled: false, preserve: true)
        let unavailable = try await snapshot(enabled: false, preserve: false)
        try check(enabled != nil && enabled == transientLock, "temporary disabled button must keep enabled pixels")
        try check(enabled != unavailable, "persistent unavailable button must remain visually distinct")
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
        try checkLayers(view, image: image, scroll: scroll, content: content)
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
        try checkLayers(view, image: image, scroll: scroll, content: content)

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

        try await checkImportPresentation(view, canvas: canvas, image: replacement, host: host, strokes: { strokes.count })

        update(view, image: replacement, tool: .block)
        view.canvasViewDidBeginUsingTool(canvas)
        try check(!view.prepareForFileSelection(), "cannot interrupt an active Pencil stroke with a picker")
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

    func checkLayers(_ view: LocalFloorPlanCanvasView, image: UIImage, scroll: UIScrollView, content: UIView) throws {
        let images = content.subviews.compactMap { $0 as? UIImageView }
        try check(images.count == 2, "source and mask layers must remain separate")
        let mask = makeImage(size: image.size)
        let originalBytes = image.pngData()
        let originalScale = scroll.zoomScale
        let originalOffset = scroll.contentOffset
        for display in [FloorPlanLayerDisplay(),
                        FloorPlanLayerDisplay(planOpacity: 0, maskOpacity: 1, showsMask: true, tint: .cyan),
                        FloorPlanLayerDisplay(planOpacity: 1, maskOpacity: 0.3, showsMask: false, tint: .red)] {
            view.update(image: image, mask: mask, tool: .block, normalizedDiameter: 0.02,
                        outline: [], scaleA: nil, scaleB: nil, scaleLabel: nil, layers: display)
            view.layoutIfNeeded()
            try check(images[0].image === image && image.pngData() == originalBytes, "layer display must not change source pixels")
            try check(abs(images[0].alpha - CGFloat(display.planOpacity)) < 1e-6 &&
                      abs(images[1].alpha - CGFloat(display.maskOpacity)) < 1e-6,
                      "apply independent layer opacity")
            try check(images[1].isHidden == !display.showsMask && images[1].tintColor == display.tint.color,
                      "apply mask visibility and color")
            try check(abs(scroll.zoomScale - originalScale) < 1e-6 && scroll.contentOffset == originalOffset,
                      "layer-only changes must preserve fit/zoom and pan")
        }
        update(view, image: image, tool: .block)
        view.layoutIfNeeded()
        guard let markers = content.subviews.last else { throw Failure(message: "markers missing") }
        markers.layer.displayIfNeeded()
        update(view, image: image, tool: .block)
        try check(!markers.layer.needsDisplay(), "unchanged input must not redraw markers")
        try check(!view.layer.needsLayout(), "unchanged input must not invalidate canvas layout")
        view.update(image: image, mask: nil, tool: .block, normalizedDiameter: 0.02,
                    outline: [], scaleA: nil, scaleB: nil, scaleLabel: nil,
                    layers: FloorPlanLayerDisplay(planOpacity: 0.4, maskOpacity: 0.3, showsMask: false, tint: .red))
        try check(!markers.layer.needsDisplay() && !view.layer.needsLayout(),
                  "opacity/color-only changes must not invalidate markers or canvas layout")
        view.layoutSubviews()
        try check(!markers.layer.needsDisplay(), "same viewport/zoom must not redraw markers")
        view.update(image: image, mask: nil, tool: .block, normalizedDiameter: 0.02,
                    outline: [LocalPlanPoint(x: 0.1, y: 0.1)], scaleA: nil, scaleB: nil, scaleLabel: nil)
        try check(markers.layer.needsDisplay(), "actual marker changes must redraw")
        update(view, image: image, tool: .block)
    }

    func checkEditorLayout(in host: UIView) async throws {
        let source = makeImage(size: CGSize(width: 400, height: 1_000))
        let draft = FloorPlanDraftStore(importer: CanvasCheckImporter(png: source.pngData()!))
        let app = InstructorStore(floorPlanDraft: draft)
        let controller = UIHostingController(rootView: FloorPlanCreateView().environment(app).environment(draft))
        let parent = host.next as? UIViewController
        parent?.addChild(controller)
        controller.view.frame = host.bounds
        host.addSubview(controller.view)
        controller.didMove(toParent: parent)
        defer {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        draft.importImage(from: URL(fileURLWithPath: "/canvas-check.png"))
        for _ in 0..<100 {
            if draft.image != nil && !draft.isProcessing { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await drain()
        controller.view.layoutIfNeeded()
        guard let canvas: LocalFloorPlanCanvasView = descendant(in: controller.view),
              let scroll = canvas.subviews.compactMap({ $0 as? UIScrollView }).first else {
            throw Failure(message: "actual SwiftUI editor canvas missing")
        }
        let viewport = canvas.bounds.size
        let scale = scroll.zoomScale
        let oldMask = draft.maskImage
        draft.appendStroke(LocalEditStroke(mode: .block, points: [LocalPlanPoint(x: 0.5, y: 0.5)], normalizedDiameter: 0.02))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try check(draft.isProcessing && draft.maskImage === oldMask && oldMask != nil,
                  "retain colored preview throughout pending stroke replay")
        try check(canvas.bounds.size == viewport && abs(scroll.zoomScale - scale) < 1e-6,
                  "processing indicator must not resize or refit actual editor")
        for _ in 0..<100 {
            if !draft.isProcessing { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        controller.view.layoutIfNeeded()
        try check(!draft.isProcessing && draft.maskImage != nil && draft.resolvedGrid != nil, "replay must finish")
        try check(canvas.bounds.size == viewport && abs(scroll.zoomScale - scale) < 1e-6,
                  "processing completion must not resize actual editor")
        let originalImage = draft.previewImage
        let originalMask = draft.maskImage
        scroll.setZoomScale(max(scroll.minimumZoomScale * 2, scroll.minimumZoomScale), animated: false)
        let zoomBeforeFailure = scroll.zoomScale
        draft.importImage(from: URL(fileURLWithPath: "/failure.png"))
        try check(draft.isImporting && !draft.isReplayingEdits, "replacement has visible progress, not quiet replay")
        for _ in 0..<100 {
            if !draft.isProcessing { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await drain()
        controller.view.layoutIfNeeded()
        try check(draft.errorMessage != nil && draft.previewImage === originalImage && draft.maskImage === originalMask,
                  "failed replacement must retain displayed image/mask identity")
        try check(canvas.bounds.size == viewport && abs(scroll.zoomScale - zoomBeforeFailure) < 1e-6,
                  "replacement failure/error overlay must preserve viewport and zoom")
    }

    func descendant<T: UIView>(in view: UIView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match: T = descendant(in: child) { return match }
        }
        return nil
    }

    func checkImportPresentation(_ view: LocalFloorPlanCanvasView, canvas: PKCanvasView, image: UIImage,
                                 host: UIView, strokes: () -> Int) async throws {
        update(view, image: image, tool: .block)
        let presenter = FloorPlanImportPresentation()
        presenter.anchor = host
        presenter.canvas = view
        let count = strokes()
        var focusDismissals = 0
        presenter.request { focusDismissals += 1 }
        try check(presenter.isPreparing && !presenter.isPresented, "picker must not present in the input event")
        try check(!canvas.isUserInteractionEnabled, "canvas suspended before picker presentation")
        presenter.request { focusDismissals += 1 }
        try await drain()
        try check(presenter.isPresented && focusDismissals == 1, "deduplicate requests and present on later turn")
        presenter.finish()
        try check(strokes() == count && !presenter.isPresented, "picker cancellation must preserve edits")
        try check(canvas.isUserInteractionEnabled, "cancellation restores the previous drawing tool")

        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        presenter.request {}
        try await drain()
        try check(presenter.isPreparing && !presenter.isPresented, "wait for keyboard dismissal")
        NotificationCenter.default.post(name: UIResponder.keyboardDidHideNotification, object: nil)
        try await drain()
        try check(presenter.isPresented, "present only after keyboard didHide")
        presenter.finish()

        presenter.request {}
        presenter.finish() // navigation away before the queued presentation
        try await drain()
        try check(!presenter.isPresented && !presenter.isPreparing, "no stale presentation after leaving screen")

        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        presenter.request {}
        try await Task.sleep(for: .milliseconds(2_100))
        try check(!presenter.isPreparing && !presenter.isPresented && presenter.message != nil,
                  "missing keyboard callback must recover, never force-present or hang")
        NotificationCenter.default.post(name: UIResponder.keyboardDidHideNotification, object: nil)
        try await drain()
        try check(!presenter.isPresented, "late keyboard callback must not reopen cancelled request")

        // UIKit first-responder release, including when the software keyboard is absent.
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 150, height: 40))
        host.addSubview(field)
        field.becomeFirstResponder()
        try check(field.isFirstResponder, "test text field must own focus")
        presenter.request {}
        try check(!field.isFirstResponder, "request must end editing in the owning window")
        presenter.finish()
        field.removeFromSuperview()

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

private struct CanvasCheckImporter: FloorPlanImporting {
    let png: Data
    func process(url: URL) async throws -> LocalExtractionResult {
        if url.lastPathComponent == "failure.png" { throw LocalFloorPlanError.invalid("Test replacement failed") }
        return LocalExtractionResult(image: LocalImportedImage(pngData: png, width: 400, height: 1_000, fileName: "canvas-check.png"),
            baseGrid: LocalObstacleGrid(columns: 200, rows: 500, cellSizePixels: 2, blocked: [UInt8](repeating: 0, count: 100_000)))
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
