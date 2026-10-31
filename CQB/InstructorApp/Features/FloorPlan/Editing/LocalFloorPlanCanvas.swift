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
    var selection: [LocalPlanPoint] = []
    var pendingBrushStrokes: [LocalEditStroke] = []
    var scaleA: LocalPlanPoint?
    var scaleB: LocalPlanPoint?
    var scaleLabel: String? = nil
    var importPresentation: FloorPlanImportPresentation? = nil
    var layers = FloorPlanLayerDisplay()
    var onStroke: (LocalEditStroke) -> Void
    var onPoint: (LocalPlanPoint) -> Void
    var onScaleMarkerMoved: (LocalScaleMarker, LocalPlanPoint) -> Void = { _, _ in }
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> LocalFloorPlanCanvasView {
        let view = LocalFloorPlanCanvasView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: LocalFloorPlanCanvasView, context: Context) {
        importPresentation?.canvas = view
        view.onStroke = onStroke
        view.onPoint = onPoint
        view.onScaleMarkerMoved = onScaleMarkerMoved
        view.onEditingChanged = onEditingChanged
        view.update(image: image, mask: mask, tool: tool,
                    normalizedDiameter: normalizedDiameter, selection: selection,
                    pendingBrushStrokes: pendingBrushStrokes,
                    scaleA: scaleA, scaleB: scaleB, scaleLabel: scaleLabel, layers: layers)
    }

    static func dismantleUIView(_ view: LocalFloorPlanCanvasView, coordinator: ()) {
        view.tearDown()
    }
}

final class LocalFloorPlanCanvasView: UIView, UIScrollViewDelegate, PKCanvasViewDelegate {
    var onStroke: ((LocalEditStroke) -> Void)?
    var onPoint: ((LocalPlanPoint) -> Void)?
    var onScaleMarkerMoved: ((LocalScaleMarker, LocalPlanPoint) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let imageView = UIImageView()
    private let obstacleImageView = UIImageView()
    private let markersView = LocalFloorPlanMarkersView()
    private let canvasView = PKCanvasView()
    private lazy var placementTap = UITapGestureRecognizer(target: self, action: #selector(placePoint(_:)))
    private lazy var scaleDrag = UIPanGestureRecognizer(target: self, action: #selector(dragScaleMarker(_:)))
    private var tool: LocalCanvasTool = .move
    private var normalizedDiameter = 0.01
    private var imageSize: CGSize = .zero
    private var appliedImageSize: CGSize = .zero
    private var appliedViewportSize: CGSize = .zero
    private var needsFit = true
    private var isUsingTool = false
    private var isClearingDrawing = false
    private var isCommitting = false
    private var editingReported = false
    private var inputSuspended = false
    private var appliedInkWidth: CGFloat?
    private var appliedInkTool: LocalCanvasTool?
    private var appliedMask: UIImage?
    private var completionTask: DispatchWorkItem?
    private var strokeContext: (mode: LocalEditMode, diameter: Double)?
    private var draggedScaleMarker: LocalScaleMarker?

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
        if scrollView.frame != bounds { scrollView.frame = bounds }
        configureImageBounds()
        if needsFit || appliedViewportSize != bounds.size {
            appliedViewportSize = bounds.size
            updateZoomLimits()
        }
    }

    func update(image: UIImage, mask: UIImage?, tool: LocalCanvasTool,
                normalizedDiameter: Double, selection: [LocalPlanPoint],
                pendingBrushStrokes: [LocalEditStroke],
                scaleA: LocalPlanPoint?, scaleB: LocalPlanPoint?, scaleLabel: String?,
                layers: FloorPlanLayerDisplay = FloorPlanLayerDisplay()) {
        let imageChanged = imageView.image !== image
        if imageChanged {
            discardPendingDrawing()
            needsFit = true
            imageView.image = image
            imageSize = CGSize(width: image.cgImage?.width ?? Int(image.size.width),
                               height: image.cgImage?.height ?? Int(image.size.height))
        }
        let planAlpha = CGFloat(min(1, max(0, layers.planOpacity)))
        if imageView.alpha != planAlpha { imageView.alpha = planAlpha }
        if appliedMask !== mask {
            appliedMask = mask
            obstacleImageView.image = mask?.withRenderingMode(.alwaysTemplate)
            let frame = CGRect(origin: .zero, size: mask?.size ?? .zero)
            if obstacleImageView.frame != frame { obstacleImageView.frame = frame }
        }
        let maskAlpha = CGFloat(min(1, max(0, layers.maskOpacity)))
        if obstacleImageView.alpha != maskAlpha { obstacleImageView.alpha = maskAlpha }
        if obstacleImageView.tintColor != layers.tint.color { obstacleImageView.tintColor = layers.tint.color }
        if obstacleImageView.isHidden != !layers.showsMask { obstacleImageView.isHidden = !layers.showsMask }
        let toolChanged = self.tool != tool
        self.tool = tool
        let diameter = normalizedDiameter.isFinite ? max(0.0001, normalizedDiameter) : 0.01
        let diameterChanged = self.normalizedDiameter != diameter
        self.normalizedDiameter = diameter
        markersView.update(selection: selection, pendingBrushStrokes: pendingBrushStrokes,
                           brushDiameter: diameter, scaleA: scaleA, scaleB: scaleB, scaleLabel: scaleLabel)
        if toolChanged || imageChanged { updateInteraction() }
        else if diameterChanged { updateInkTool() }
        if imageChanged { setNeedsLayout() }
    }

    func tearDown() {
        onStroke = nil
        onPoint = nil
        onScaleMarkerMoved = nil
        onEditingChanged = nil
        completionTask?.cancel()
        completionTask = nil
        canvasView.delegate = nil
        scrollView.delegate = nil
        strokeContext = nil
        draggedScaleMarker = nil
    }

    /// Called from a button event, never from updateUIView/layoutSubviews.
    func prepareForFileSelection() -> Bool {
        guard !isUsingTool, !isCommitting else { return false }
        completionTask?.cancel()
        commitCompletedDrawing()
        inputSuspended = true
        updateInteraction()
        canvasView.resignFirstResponder()
        // Keep any late stroke context: cancelling the picker must not lose that edit.
        return true
    }

    func resumeAfterFileSelection() {
        inputSuspended = false
        updateInteraction()
        // Do not becomeFirstResponder here; resume input only on the next user gesture.
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
        obstacleImageView.tintAdjustmentMode = .normal
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
        contentView.addGestureRecognizer(scaleDrag)
        // Placement is a single tap; a two-finger pan never places an accidental point.
        placementTap.numberOfTouchesRequired = 1
        placementTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                          NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        scaleDrag.maximumNumberOfTouches = 1
        scaleDrag.allowedTouchTypes = placementTap.allowedTouchTypes
        accessibilityLabel = "도면 편집 영역"
    }

    private func updateInteraction() {
        let isDrawing = tool == .brush
        canvasView.isUserInteractionEnabled = isDrawing && !inputSuspended
        placementTap.isEnabled = !inputSuspended && (tool == .pen || tool == .scaleA || tool == .scaleB)
        scaleDrag.isEnabled = !inputSuspended && (tool == .scaleA || tool == .scaleB)
        scrollView.isUserInteractionEnabled = !inputSuspended
        scrollView.panGestureRecognizer.minimumNumberOfTouches = tool == .move ? 1 : 2
        updateInkTool()
    }

    private func updateInkTool() {
        guard !isUsingTool, !inputSuspended else { return }
        let width = CGFloat(normalizedDiameter) * max(1, min(imageSize.width, imageSize.height))
        guard appliedInkWidth != width || appliedInkTool != tool else { return }
        canvasView.tool = PKInkingTool(.monoline, color: UIColor.systemOrange.withAlphaComponent(0.7), width: width)
        appliedInkWidth = width
        appliedInkTool = tool
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
        markersView.setNeedsDisplay()
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
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if scrollView.contentInset != inset { scrollView.contentInset = inset }
        markersView.viewScale = scrollView.zoomScale
    }

    @objc private func placePoint(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, !isUsingTool, !inputSuspended,
              tool == .pen || tool == .scaleA || tool == .scaleB else { return }
        let position = recognizer.location(in: contentView)
        guard position.x >= 0, position.y >= 0, position.x <= imageSize.width,
              position.y <= imageSize.height, imageSize.width > 0, imageSize.height > 0 else { return }
        onPoint?(LocalPlanPoint(x: position.x / imageSize.width, y: position.y / imageSize.height))
    }

    @objc private func dragScaleMarker(_ recognizer: UIPanGestureRecognizer) {
        guard !inputSuspended, imageSize.width > 0, imageSize.height > 0,
              tool == .scaleA || tool == .scaleB else { return }
        let position = recognizer.location(in: contentView)
        let point = LocalPlanPoint(
            x: min(1, max(0, position.x / imageSize.width)),
            y: min(1, max(0, position.y / imageSize.height))
        )
        switch recognizer.state {
        case .began:
            let threshold = 32 / max(0.001, scrollView.zoomScale)
            let candidates: [(LocalScaleMarker, LocalPlanPoint?)] = [(.a, markersView.scaleA), (.b, markersView.scaleB)]
            draggedScaleMarker = candidates.compactMap { marker, candidate -> (LocalScaleMarker, CGFloat)? in
                guard let candidate else { return nil }
                let candidatePoint = CGPoint(x: candidate.x * imageSize.width, y: candidate.y * imageSize.height)
                let distance = hypot(candidatePoint.x - position.x, candidatePoint.y - position.y)
                return distance <= threshold ? (marker, distance) : nil
            }
            .min(by: { $0.1 < $1.1 })?.0
        case .changed:
            if let draggedScaleMarker { onScaleMarkerMoved?(draggedScaleMarker, point) }
        case .ended, .cancelled, .failed:
            if let draggedScaleMarker { onScaleMarkerMoved?(draggedScaleMarker, point) }
            draggedScaleMarker = nil
        default:
            break
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        guard !inputSuspended else { return }
        // A quick next stroke may start before the queued end-of-stroke callback runs.
        completionTask?.cancel()
        commitCompletedDrawing()
        guard tool == .brush else { return }
        isUsingTool = true
        // The stroke remains a pending selection until the user chooses Add or Delete.
        strokeContext = (.block, normalizedDiameter)
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
    var selection: [LocalPlanPoint] = []
    var pendingBrushStrokes: [LocalEditStroke] = []
    var brushDiameter = 0.006
    var scaleA: LocalPlanPoint?
    var scaleB: LocalPlanPoint?
    var scaleLabel: String?
    var viewScale: CGFloat = 1 { didSet { if viewScale != oldValue { setNeedsDisplay() } } }

    func update(selection: [LocalPlanPoint],
                pendingBrushStrokes: [LocalEditStroke], brushDiameter: Double,
                scaleA: LocalPlanPoint?, scaleB: LocalPlanPoint?, scaleLabel: String?) {
        guard self.selection != selection
                || self.pendingBrushStrokes != pendingBrushStrokes || self.brushDiameter != brushDiameter
                || self.scaleA != scaleA || self.scaleB != scaleB || self.scaleLabel != scaleLabel else { return }
        self.selection = selection
        self.pendingBrushStrokes = pendingBrushStrokes
        self.brushDiameter = brushDiameter
        self.scaleA = scaleA
        self.scaleB = scaleB
        self.scaleLabel = scaleLabel
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let unit = 1 / max(0.001, viewScale)
        context.setLineWidth(2 * unit)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // Temporary selection points remain numbered until the user applies them.
        if let first = selection.first {
            context.setStrokeColor(UIColor.systemOrange.cgColor)
            context.move(to: cg(first))
            for point in selection.dropFirst() { context.addLine(to: cg(point)) }
            if selection.count >= 3 { context.closePath() }
            context.strokePath()
            for (index, point) in selection.enumerated() {
                marker(point, label: String(index + 1), color: .systemOrange, unit: unit, context: context)
            }
        }

        context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(CGFloat(brushDiameter) * max(1, min(bounds.width, bounds.height)))
        for stroke in pendingBrushStrokes {
            guard let first = stroke.points.first else { continue }
            context.move(to: cg(first))
            for point in stroke.points.dropFirst() { context.addLine(to: cg(point)) }
            context.strokePath()
        }

        if let scaleA, let scaleB {
            context.setLineWidth(2 * unit)
            context.setStrokeColor(UIColor.systemRed.cgColor)
            context.setLineDash(phase: 0, lengths: [])
            context.move(to: cg(scaleA))
            context.addLine(to: cg(scaleB))
            context.strokePath()
            if let scaleLabel {
                let midpoint = CGPoint(x: (cg(scaleA).x + cg(scaleB).x) / 2,
                                       y: (cg(scaleA).y + cg(scaleB).y) / 2)
                (scaleLabel as NSString).draw(at: CGPoint(x: midpoint.x, y: midpoint.y - 22 * unit),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14 * unit),
                                     .foregroundColor: UIColor.white])
            }
        }
        if let scaleA { scaleMarker(scaleA, label: "A", unit: unit, context: context) }
        if let scaleB { scaleMarker(scaleB, label: "B", unit: unit, context: context) }
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

    private func scaleMarker(_ point: LocalPlanPoint, label: String, unit: CGFloat, context: CGContext) {
        let position = cg(point)
        let diameter = 36 * unit
        let circle = CGRect(
            x: position.x - diameter / 2,
            y: position.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        context.setFillColor(UIColor.systemRed.cgColor)
        context.fillEllipse(in: circle)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2 * unit)
        context.strokeEllipse(in: circle.insetBy(dx: unit, dy: unit))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (label as NSString).draw(
            in: circle.offsetBy(dx: 0, dy: 6 * unit),
            withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 16 * unit),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
        )
    }
}
