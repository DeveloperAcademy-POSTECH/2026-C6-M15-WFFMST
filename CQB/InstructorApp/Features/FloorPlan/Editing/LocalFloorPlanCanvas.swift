import PencilKit
import SwiftUI
import UIKit

/// Presents image-space input; the Store owns editing history and rasterization.
struct LocalFloorPlanCanvas: UIViewRepresentable {
    var image: UIImage
    /// The mask's logical size is its grid extent in source image pixels.
    /// For a one-pixel-per-cell CGImage, create UIImage(scale: 1 / cellSize).
    var mask: UIImage?
    var tool: LocalCanvasTool
    var normalizedDiameter: Double
    var outline: [LocalPlanPoint]
    var scaleA: LocalPlanPoint?
    var scaleB: LocalPlanPoint?
    var scaleLabel: String? = nil
    var onStroke: (LocalEditStroke) -> Void
    var onPoint: (LocalPlanPoint) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> LocalFloorPlanCanvasView {
        let view = LocalFloorPlanCanvasView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: LocalFloorPlanCanvasView, context: Context) {
        view.onStroke = onStroke
        view.onPoint = onPoint
        view.onEditingChanged = onEditingChanged
        view.update(image: image, mask: mask, tool: tool,
                    normalizedDiameter: normalizedDiameter, outline: outline,
                    scaleA: scaleA, scaleB: scaleB, scaleLabel: scaleLabel)
    }

    static func dismantleUIView(_ view: LocalFloorPlanCanvasView, coordinator: ()) {
        view.tearDown()
    }
}

final class LocalFloorPlanCanvasView: UIView, UIScrollViewDelegate, PKCanvasViewDelegate {
    var onStroke: ((LocalEditStroke) -> Void)?
    var onPoint: ((LocalPlanPoint) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let imageView = UIImageView()
    private let obstacleImageView = UIImageView()
    private let markersView = LocalFloorPlanMarkersView()
    private let canvasView = PKCanvasView()
    private lazy var placementTap = UITapGestureRecognizer(target: self, action: #selector(placePoint(_:)))
    private var tool: LocalCanvasTool = .move
    private var normalizedDiameter = 0.01
    private var imageSize: CGSize = .zero
    private var appliedImageSize: CGSize = .zero
    private var needsFit = true
    private var isUsingTool = false
    private var isClearingDrawing = false
    private var isCommitting = false
    private var editingReported = false
    private var completionTask: DispatchWorkItem?
    private var strokeContext: (mode: LocalEditMode, diameter: Double)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        configureImageBounds()
        updateZoomLimits()
    }

    func update(image: UIImage, mask: UIImage?, tool: LocalCanvasTool,
                normalizedDiameter: Double, outline: [LocalPlanPoint],
                scaleA: LocalPlanPoint?, scaleB: LocalPlanPoint?, scaleLabel: String?) {
        if imageView.image !== image {
            discardPendingDrawing()
            needsFit = true
        }
        imageView.image = image
        imageSize = CGSize(width: image.cgImage?.width ?? Int(image.size.width),
                           height: image.cgImage?.height ?? Int(image.size.height))
        obstacleImageView.image = mask
        obstacleImageView.frame = CGRect(origin: .zero, size: mask?.size ?? .zero)
        self.tool = tool
        self.normalizedDiameter = normalizedDiameter.isFinite ? max(0.0001, normalizedDiameter) : 0.01
        markersView.outline = outline
        markersView.scaleA = scaleA
        markersView.scaleB = scaleB
        markersView.scaleLabel = scaleLabel
        markersView.setNeedsDisplay()
        updateInteraction()
        setNeedsLayout()
    }

    func tearDown() {
        onStroke = nil
        onPoint = nil
        onEditingChanged = nil
        completionTask?.cancel()
        completionTask = nil
        canvasView.delegate = nil
        scrollView.delegate = nil
        strokeContext = nil
    }

    private func configureViews() {
        backgroundColor = .secondarySystemBackground
        scrollView.delegate = self
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        contentView.backgroundColor = .white
        contentView.clipsToBounds = true
        scrollView.addSubview(contentView)
        imageView.contentMode = .scaleToFill
        contentView.addSubview(imageView)
        obstacleImageView.contentMode = .scaleToFill
        obstacleImageView.alpha = 0.65
        obstacleImageView.layer.magnificationFilter = .nearest
        obstacleImageView.layer.minificationFilter = .nearest
        contentView.addSubview(obstacleImageView)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = self
        contentView.addSubview(canvasView)
        markersView.backgroundColor = .clear
        markersView.isOpaque = false
        markersView.isUserInteractionEnabled = false
        contentView.addSubview(markersView)
        contentView.addGestureRecognizer(placementTap)
        // Placement is a single tap; a two-finger pan never places an accidental point.
        placementTap.numberOfTouchesRequired = 1
        placementTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                          NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        accessibilityLabel = "도면 편집 영역"
    }

    private func updateInteraction() {
        let isDrawing = tool == .block || tool == .open
        canvasView.isUserInteractionEnabled = isDrawing
        placementTap.isEnabled = tool == .outline || tool == .scaleA || tool == .scaleB
        scrollView.panGestureRecognizer.minimumNumberOfTouches = tool == .move ? 1 : 2
        updateInkTool()
    }

    private func updateInkTool() {
        guard !isUsingTool else { return }
        let width = CGFloat(normalizedDiameter) * max(1, min(imageSize.width, imageSize.height))
        let color: UIColor = tool == .open ? .systemGreen : .systemOrange
        canvasView.tool = PKInkingTool(.monoline, color: color.withAlphaComponent(0.7), width: width)
    }

    private func configureImageBounds() {
        guard imageSize != appliedImageSize else { return }
        // Changing frame while zoomed also changes bounds; reset the transform first.
        scrollView.minimumZoomScale = 0.001
        scrollView.zoomScale = 1
        let frame = CGRect(origin: .zero, size: imageSize)
        contentView.frame = frame
        imageView.frame = frame
        canvasView.frame = frame
        markersView.frame = frame
        scrollView.contentSize = imageSize
        appliedImageSize = imageSize
        needsFit = true
    }

    private func updateZoomLimits() {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let previousMinimum = scrollView.minimumZoomScale
        scrollView.maximumZoomScale = max(fit * 12, 8)
        scrollView.minimumZoomScale = fit
        if needsFit || abs(scrollView.zoomScale - previousMinimum) < 0.0001 || scrollView.zoomScale < fit {
            scrollView.zoomScale = fit
            needsFit = false
        }
        centerContent()
        updateInkTool()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }

    private func centerContent() {
        let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        markersView.viewScale = scrollView.zoomScale
    }

    @objc private func placePoint(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, !isUsingTool,
              tool == .outline || tool == .scaleA || tool == .scaleB else { return }
        let position = recognizer.location(in: contentView)
        guard position.x >= 0, position.y >= 0, position.x <= imageSize.width,
              position.y <= imageSize.height, imageSize.width > 0, imageSize.height > 0 else { return }
        onPoint?(LocalPlanPoint(x: position.x / imageSize.width, y: position.y / imageSize.height))
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        // A quick next stroke may start before the queued end-of-stroke callback runs.
        completionTask?.cancel()
        commitCompletedDrawing()
        guard tool == .block || tool == .open else { return }
        isUsingTool = true
        strokeContext = (tool == .block ? .block : .open, normalizedDiameter)
        reportEditing(true)
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isUsingTool = false
        scheduleCompletedDrawing()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        // PencilKit can publish its final path after DidEndUsingTool.
        guard !isClearingDrawing, !isUsingTool, !isCommitting else { return }
        scheduleCompletedDrawing()
    }

    private func scheduleCompletedDrawing() {
        guard !isClearingDrawing else { return }
        completionTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.commitCompletedDrawing() }
        completionTask = task
        DispatchQueue.main.async(execute: task)
    }

    private func commitCompletedDrawing() {
        guard !isUsingTool, !isCommitting, !isClearingDrawing else { return }
        completionTask = nil
        guard let context = strokeContext else { return }
        let strokes = canvasView.drawing.strokes
        guard !strokes.isEmpty else {
            // Keep context for a final DrawingDidChange that arrives later.
            reportEditing(false)
            return
        }
        isCommitting = true
        for stroke in strokes {
            let points = stroke.path.map { point in
                let position = point.location.applying(stroke.transform)
                return LocalPlanPoint(x: min(1, max(0, position.x / max(1, imageSize.width))),
                                      y: min(1, max(0, position.y / max(1, imageSize.height))))
            }
            if !points.isEmpty {
                onStroke?(LocalEditStroke(mode: context.mode, points: points, normalizedDiameter: context.diameter))
            }
        }
        clearDrawing()
        strokeContext = nil
        isCommitting = false
        reportEditing(false)
        updateInkTool()
    }

    private func clearDrawing() {
        isClearingDrawing = true
        canvasView.drawing = PKDrawing()
        isClearingDrawing = false
    }

    private func discardPendingDrawing() {
        completionTask?.cancel()
        completionTask = nil
        strokeContext = nil
        isUsingTool = false
        clearDrawing()
        if editingReported {
            // updateUIView must not synchronously mutate observed SwiftUI state.
            editingReported = false
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.editingReported else { return }
                self.onEditingChanged?(false)
            }
        }
    }

    private func reportEditing(_ value: Bool) {
        guard editingReported != value else { return }
        editingReported = value
        onEditingChanged?(value)
    }
}

private final class LocalFloorPlanMarkersView: UIView {
    var outline: [LocalPlanPoint] = []
    var scaleA: LocalPlanPoint?
    var scaleB: LocalPlanPoint?
    var scaleLabel: String?
    var viewScale: CGFloat = 1 { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let unit = 1 / max(0.001, viewScale)
        context.setLineWidth(2 * unit)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(UIColor.systemPurple.cgColor)
        if let first = outline.first {
            context.move(to: cg(first))
            for point in outline.dropFirst() { context.addLine(to: cg(point)) }
            if outline.count >= 3 { context.closePath() }
            context.strokePath()
            for (index, point) in outline.enumerated() {
                marker(point, label: String(index + 1), color: .systemPurple, unit: unit, context: context)
            }
        }
        if let scaleA, let scaleB {
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineDash(phase: 0, lengths: [5 * unit, 3 * unit])
            context.move(to: cg(scaleA))
            context.addLine(to: cg(scaleB))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            if let scaleLabel {
                let midpoint = CGPoint(x: (cg(scaleA).x + cg(scaleB).x) / 2,
                                       y: (cg(scaleA).y + cg(scaleB).y) / 2)
                (scaleLabel as NSString).draw(at: CGPoint(x: midpoint.x, y: midpoint.y - 22 * unit),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14 * unit),
                                     .foregroundColor: UIColor.systemBlue,
                                     .backgroundColor: UIColor.white.withAlphaComponent(0.8)])
            }
        }
        if let scaleA { marker(scaleA, label: "A", color: .systemBlue, unit: unit, context: context) }
        if let scaleB { marker(scaleB, label: "B", color: .systemBlue, unit: unit, context: context) }
    }

    private func cg(_ point: LocalPlanPoint) -> CGPoint {
        CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)
    }

    private func marker(_ point: LocalPlanPoint, label: String, color: UIColor, unit: CGFloat, context: CGContext) {
        let position = cg(point)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: position.x - 4 * unit, y: position.y - 4 * unit,
                                      width: 8 * unit, height: 8 * unit))
        (label as NSString).draw(at: CGPoint(x: position.x + 6 * unit, y: position.y - 8 * unit),
                                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14 * unit),
                                                 .foregroundColor: color,
                                                 .backgroundColor: UIColor.white.withAlphaComponent(0.8)])
    }
}
