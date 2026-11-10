import CQBDesignSystem
import PencilKit
import SwiftUI
import UIKit

enum LocalScaleMarkerAppearance: Equatable {
    case standard
    case scanHeading
}

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
    var scaleALabel = "A"
    var scaleBLabel = "B"
    var scaleMarkerAppearance: LocalScaleMarkerAppearance = .standard
    var showsScanStartSelection = false
    var usesTransparentBackground = false
    var maximumInitialDisplaySize: CGSize? = nil
    var imageToneOverlayOpacity: CGFloat = 0
    var checkpointMarkers: [LocalScanCheckpointMarker] = []
    var checkpointAppearance: LocalScanCheckpointAppearance = .labeled
    var importPresentation: FloorPlanImportPresentation? = nil
    var layers = FloorPlanLayerDisplay()
    var onStroke: (LocalEditStroke) -> Void
    var onPoint: (LocalPlanPoint) -> Void
    var onCheckpointTap: ((Int) -> Void)? = nil
    var onScaleMarkerMoved: (LocalScaleMarker, LocalPlanPoint) -> Void = { _, _ in }
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onDisplayScaleChanged: (CGFloat) -> Void = { _ in }

    func makeUIView(context: Context) -> LocalFloorPlanCanvasView {
        let view = LocalFloorPlanCanvasView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: LocalFloorPlanCanvasView, context: Context) {
        importPresentation?.canvas = view
        view.onStroke = onStroke
        view.onPoint = onPoint
        view.onCheckpointTap = onCheckpointTap
        view.onScaleMarkerMoved = onScaleMarkerMoved
        view.onEditingChanged = onEditingChanged
        view.onDisplayScaleChanged = onDisplayScaleChanged
        view.update(image: image, mask: mask, tool: tool,
                    normalizedDiameter: normalizedDiameter, selection: selection,
                    pendingBrushStrokes: pendingBrushStrokes,
                    scaleA: scaleA, scaleB: scaleB, scaleLabel: scaleLabel,
                    scaleALabel: scaleALabel, scaleBLabel: scaleBLabel,
                    scaleMarkerAppearance: scaleMarkerAppearance,
                    showsScanStartSelection: showsScanStartSelection,
                    usesTransparentBackground: usesTransparentBackground,
                    maximumInitialDisplaySize: maximumInitialDisplaySize,
                    imageToneOverlayOpacity: imageToneOverlayOpacity,
                    checkpointMarkers: checkpointMarkers,
                    checkpointAppearance: checkpointAppearance, layers: layers)
    }

    static func dismantleUIView(_ view: LocalFloorPlanCanvasView, coordinator: ()) {
        view.tearDown()
    }
}

final class LocalFloorPlanCanvasView: UIView, UIScrollViewDelegate, PKCanvasViewDelegate,
                                      UIGestureRecognizerDelegate {
    var onStroke: ((LocalEditStroke) -> Void)?
    var onPoint: ((LocalPlanPoint) -> Void)?
    var onCheckpointTap: ((Int) -> Void)?
    var onScaleMarkerMoved: ((LocalScaleMarker, LocalPlanPoint) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var onDisplayScaleChanged: ((CGFloat) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let imageView = UIImageView()
    private var sourceImage: UIImage?
    private var appliedToneOpacity: CGFloat = 0
    private let obstacleImageView = UIImageView()
    private let markersView = LocalFloorPlanMarkersView()
    private let canvasView = PKCanvasView()
    private lazy var placementTap = UITapGestureRecognizer(target: self, action: #selector(placePoint(_:)))
    private lazy var scaleDrag = UIPanGestureRecognizer(target: self, action: #selector(dragScaleMarker(_:)))
    private lazy var livePreviewGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(trackDrawingGesture(_:)))
        gesture.minimumPressDuration = 0
        gesture.allowableMovement = .greatestFiniteMagnitude
        gesture.numberOfTouchesRequired = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        gesture.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        return gesture
    }()
    private var tool: LocalCanvasTool = .move
    private var normalizedDiameter = 0.01
    private var imageSize: CGSize = .zero
    private var maximumInitialDisplaySize: CGSize?
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
    private var liveBrushPoints: [LocalPlanPoint] = []
    private var draggedScaleMarker: LocalScaleMarker?
    private var lastReportedDisplayScale: CGFloat?

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
                scaleALabel: String, scaleBLabel: String,
                scaleMarkerAppearance: LocalScaleMarkerAppearance,
                showsScanStartSelection: Bool,
                usesTransparentBackground: Bool,
                maximumInitialDisplaySize: CGSize?,
                imageToneOverlayOpacity: CGFloat,
                checkpointMarkers: [LocalScanCheckpointMarker],
                checkpointAppearance: LocalScanCheckpointAppearance,
                layers: FloorPlanLayerDisplay = FloorPlanLayerDisplay()) {
        let imageChanged = sourceImage !== image
        let toneOpacity = min(1, max(0, imageToneOverlayOpacity))
        if imageChanged {
            discardPendingDrawing()
            needsFit = true
            sourceImage = image
            imageSize = CGSize(width: image.cgImage?.width ?? Int(image.size.width),
                               height: image.cgImage?.height ?? Int(image.size.height))
        }
        if imageChanged || toneOpacity != appliedToneOpacity {
            imageView.image = tonedImage(image, opacity: toneOpacity)
            appliedToneOpacity = toneOpacity
        }
        let planAlpha = CGFloat(min(1, max(0, layers.planOpacity)))
        if imageView.alpha != planAlpha { imageView.alpha = planAlpha }
        let canvasBackground: UIColor = usesTransparentBackground ? .clear : .secondarySystemBackground
        let imageBackground: UIColor = usesTransparentBackground ? .clear : .white
        if backgroundColor != canvasBackground { backgroundColor = canvasBackground }
        if contentView.backgroundColor != imageBackground { contentView.backgroundColor = imageBackground }
        isOpaque = !usesTransparentBackground
        contentView.isOpaque = !usesTransparentBackground
        if self.maximumInitialDisplaySize != maximumInitialDisplaySize {
            self.maximumInitialDisplaySize = maximumInitialDisplaySize
            needsFit = true
            setNeedsLayout()
        }
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
                           scaleA: scaleA, scaleB: scaleB,
                           scaleLabel: scaleLabel, scaleALabel: scaleALabel,
                           scaleBLabel: scaleBLabel, scaleMarkerAppearance: scaleMarkerAppearance,
                           showsScanStartSelection: showsScanStartSelection,
                           checkpointMarkers: checkpointMarkers,
                           checkpointAppearance: checkpointAppearance)
        if toolChanged || imageChanged || tool == .move { updateInteraction() }
        else if diameterChanged { updateInkTool() }
        if imageChanged { setNeedsLayout() }
    }

    func tearDown() {
        onStroke = nil
        onPoint = nil
        onCheckpointTap = nil
        onScaleMarkerMoved = nil
        onEditingChanged = nil
        onDisplayScaleChanged = nil
        completionTask?.cancel()
        completionTask = nil
        canvasView.delegate = nil
        livePreviewGesture.delegate = nil
        scrollView.delegate = nil
        strokeContext = nil
        liveBrushPoints = []
        markersView.setLiveBrushStrokes([])
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

    private func tonedImage(_ image: UIImage, opacity: CGFloat) -> UIImage {
        guard opacity > 0, image.size.width > 0, image.size.height > 0 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let bounds = CGRect(origin: .zero, size: image.size)
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(in: bounds)
            context.cgContext.setFillColor(UIColor(DSPalette.Gray.g700).withAlphaComponent(opacity).cgColor)
            // Apply the tone without adding coverage to semitransparent pixels.
            context.cgContext.setBlendMode(.sourceAtop)
            context.cgContext.fill(bounds)
        }
    }

    private func configureViews() {
        backgroundColor = .secondarySystemBackground
        scrollView.delegate = self
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        contentView.backgroundColor = .clear
        contentView.isOpaque = false
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
        canvasView.addGestureRecognizer(livePreviewGesture)
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
        placementTap.isEnabled = !inputSuspended
            && (tool == .pen || tool == .scaleA || tool == .scaleB || tool == .alignmentPoint
                || (tool == .move && onCheckpointTap != nil))
        scaleDrag.isEnabled = !inputSuspended && (tool == .scaleA || tool == .scaleB)
        scrollView.isUserInteractionEnabled = !inputSuspended
        scrollView.panGestureRecognizer.minimumNumberOfTouches = tool == .move ? 1 : 2
        updateInkTool()
    }

    private func updateInkTool() {
        guard !isUsingTool, !inputSuspended else { return }
        let width = PKInkingTool.InkType.monoline.defaultWidth
        guard appliedInkWidth != width || appliedInkTool != tool else { return }
        // PencilKit clamps monoline ink to its own width range. Keep its ink
        // transparent and render the visible preview from the same normalized
        // diameter used by the final mask.
        canvasView.tool = PKInkingTool(.monoline, color: .clear, width: width)
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
        let viewportFit = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fit: CGFloat
        if let maximumInitialDisplaySize {
            fit = min(
                viewportFit,
                maximumInitialDisplaySize.width / imageSize.width,
                maximumInitialDisplaySize.height / imageSize.height
            )
        } else {
            fit = viewportFit
        }
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
        reportDisplayScaleIfNeeded(scrollView.zoomScale)
    }

    private func reportDisplayScaleIfNeeded(_ scale: CGFloat) {
        guard lastReportedDisplayScale.map({ abs($0 - scale) > 0.0001 }) ?? true else { return }
        lastReportedDisplayScale = scale
        DispatchQueue.main.async { [weak self] in
            self?.onDisplayScaleChanged?(scale)
        }
    }

    @objc private func placePoint(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, !isUsingTool, !inputSuspended else { return }
        let position = recognizer.location(in: contentView)
        guard position.x >= 0, position.y >= 0, position.x <= imageSize.width,
              position.y <= imageSize.height, imageSize.width > 0, imageSize.height > 0 else { return }
        if tool == .move {
            let threshold = 28 / max(0.001, scrollView.zoomScale)
            let nearest = markersView.checkpointMarkers.enumerated().compactMap { index, marker -> (Int, CGFloat)? in
                let markerPosition = CGPoint(x: marker.point.x * imageSize.width, y: marker.point.y * imageSize.height)
                let distance = hypot(markerPosition.x - position.x, markerPosition.y - position.y)
                return distance <= threshold ? (index, distance) : nil
            }
            .min(by: { $0.1 < $1.1 })
            if let nearest { onCheckpointTap?(nearest.0) }
            return
        }
        guard tool == .pen || tool == .scaleA || tool == .scaleB || tool == .alignmentPoint else { return }
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

    @objc private func trackDrawingGesture(_ recognizer: UIGestureRecognizer) {
        guard tool == .brush, !inputSuspended, imageSize.width > 0, imageSize.height > 0 else {
            clearLiveBrushPreview()
            return
        }
        let position = recognizer.location(in: contentView)
        let point = LocalPlanPoint(
            x: min(1, max(0, position.x / imageSize.width)),
            y: min(1, max(0, position.y / imageSize.height))
        )
        switch recognizer.state {
        case .began:
            liveBrushPoints = [point]
            updateLiveBrushPreview()
        case .changed:
            liveBrushPoints.append(point)
            updateLiveBrushPreview()
        case .ended:
            liveBrushPoints.append(point)
            updateLiveBrushPreview()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.canvasView.drawing.strokes.isEmpty else { return }
                self.clearLiveBrushPreview()
            }
        case .cancelled, .failed:
            clearLiveBrushPreview()
        default:
            break
        }
    }

    private func updateLiveBrushPreview() {
        guard !liveBrushPoints.isEmpty else {
            markersView.setLiveBrushStrokes([])
            return
        }
        markersView.setLiveBrushStrokes([
            LocalEditStroke(
                mode: .block,
                points: liveBrushPoints,
                normalizedDiameter: normalizedDiameter
            )
        ])
    }

    private func clearLiveBrushPreview() {
        liveBrushPoints = []
        markersView.setLiveBrushStrokes([])
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === livePreviewGesture || otherGestureRecognizer === livePreviewGesture
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
            if let editStroke = editStroke(from: stroke, context: context) { onStroke?(editStroke) }
        }
        clearDrawing()
        strokeContext = nil
        isCommitting = false
        reportEditing(false)
        updateInkTool()
    }

    private func clearDrawing() {
        clearLiveBrushPreview()
        isClearingDrawing = true
        canvasView.drawing = PKDrawing()
        isClearingDrawing = false
    }

    private func editStroke(
        from stroke: PKStroke,
        context: (mode: LocalEditMode, diameter: Double)
    ) -> LocalEditStroke? {
        let points = stroke.path.map { point in
            let position = point.location.applying(stroke.transform)
            return LocalPlanPoint(
                x: min(1, max(0, position.x / max(1, imageSize.width))),
                y: min(1, max(0, position.y / max(1, imageSize.height)))
            )
        }
        guard !points.isEmpty else { return nil }
        return LocalEditStroke(mode: context.mode, points: points, normalizedDiameter: context.diameter)
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
    private var liveBrushStrokes: [LocalEditStroke] = []
    var scaleA: LocalPlanPoint?
    var scaleB: LocalPlanPoint?
    var scaleLabel: String?
    var scaleALabel = "A"
    var scaleBLabel = "B"
    var scaleMarkerAppearance: LocalScaleMarkerAppearance = .standard
    var showsScanStartSelection = false
    var checkpointMarkers: [LocalScanCheckpointMarker] = []
    var checkpointAppearance: LocalScanCheckpointAppearance = .labeled
    var viewScale: CGFloat = 1 { didSet { if viewScale != oldValue { setNeedsDisplay() } } }

    func update(selection: [LocalPlanPoint],
                pendingBrushStrokes: [LocalEditStroke],
                scaleA: LocalPlanPoint?, scaleB: LocalPlanPoint?, scaleLabel: String?,
                scaleALabel: String, scaleBLabel: String,
                scaleMarkerAppearance: LocalScaleMarkerAppearance,
                showsScanStartSelection: Bool,
                checkpointMarkers: [LocalScanCheckpointMarker],
                checkpointAppearance: LocalScanCheckpointAppearance) {
        guard self.selection != selection
                || self.pendingBrushStrokes != pendingBrushStrokes
                || self.scaleA != scaleA || self.scaleB != scaleB || self.scaleLabel != scaleLabel
                || self.scaleALabel != scaleALabel || self.scaleBLabel != scaleBLabel
                || self.scaleMarkerAppearance != scaleMarkerAppearance
                || self.showsScanStartSelection != showsScanStartSelection
                || self.checkpointMarkers != checkpointMarkers
                || self.checkpointAppearance != checkpointAppearance else { return }
        self.selection = selection
        self.pendingBrushStrokes = pendingBrushStrokes
        self.scaleA = scaleA
        self.scaleB = scaleB
        self.scaleLabel = scaleLabel
        self.scaleALabel = scaleALabel
        self.scaleBLabel = scaleBLabel
        self.scaleMarkerAppearance = scaleMarkerAppearance
        self.showsScanStartSelection = showsScanStartSelection
        self.checkpointMarkers = checkpointMarkers
        self.checkpointAppearance = checkpointAppearance
        setNeedsDisplay()
    }

    func setLiveBrushStrokes(_ strokes: [LocalEditStroke]) {
        guard liveBrushStrokes != strokes else { return }
        liveBrushStrokes = strokes
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
        for stroke in pendingBrushStrokes + liveBrushStrokes {
            guard let first = stroke.points.first else { continue }
            let lineWidth = CGFloat(stroke.normalizedDiameter) * max(1, min(bounds.width, bounds.height))
            context.setLineWidth(lineWidth)
            if stroke.points.count == 1 {
                let center = cg(first)
                context.setFillColor(UIColor.systemOrange.withAlphaComponent(0.8).cgColor)
                context.fillEllipse(in: CGRect(
                    x: center.x - lineWidth / 2,
                    y: center.y - lineWidth / 2,
                    width: lineWidth,
                    height: lineWidth
                ))
                continue
            }
            context.move(to: cg(first))
            for point in stroke.points.dropFirst() { context.addLine(to: cg(point)) }
            context.strokePath()
        }

        if scaleMarkerAppearance == .scanHeading, let scaleA, let scaleB {
            scanHeading(start: scaleA, direction: scaleB, unit: unit, context: context)
        } else if let scaleA, let scaleB {
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
        if scaleMarkerAppearance == .scanHeading {
            if let scaleA { scanStartMarker(scaleA, unit: unit, context: context) }
        } else {
            if let scaleA { scaleMarker(scaleA, label: scaleALabel, unit: unit, context: context) }
            if let scaleB { scaleMarker(scaleB, label: scaleBLabel, unit: unit, context: context) }
        }
        for checkpoint in checkpointMarkers {
            checkpointMarker(checkpoint, unit: unit, context: context)
        }
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
        let diameter = (label.count > 1 ? 52 : 36) * unit
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
        let font = UIFont.boldSystemFont(ofSize: (label.count > 1 ? 13 : 16) * unit)
        (label as NSString).draw(
            in: CGRect(x: circle.minX, y: position.y - font.lineHeight / 2,
                       width: circle.width, height: font.lineHeight),
            withAttributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func scanHeading(start: LocalPlanPoint, direction: LocalPlanPoint,
                             unit: CGFloat, context: CGContext) {
        let origin = cg(start)
        let target = cg(direction)
        let deltaX = target.x - origin.x
        let deltaY = target.y - origin.y
        let radius = hypot(deltaX, deltaY)
        guard radius > 4 * unit else { return }

        let heading = atan2(deltaY, deltaX)
        let halfAngle = CGFloat.pi / 9
        context.saveGState()
        context.move(to: origin)
        context.addArc(
            center: origin,
            radius: radius,
            startAngle: heading - halfAngle,
            endAngle: heading + halfAngle,
            clockwise: false
        )
        context.closePath()
        context.clip()
        let nearColor = UIColor(DSPalette.Red.r300)
        let farColor = nearColor.withAlphaComponent(0.18)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [nearColor.cgColor, farColor.cgColor] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: origin,
                end: target,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        context.restoreGState()
    }

    private func scanStartMarker(_ point: LocalPlanPoint, unit: CGFloat, context: CGContext) {
        let position = cg(point)
        let diameter = 36 * unit
        let circle = CGRect(
            x: position.x - diameter / 2,
            y: position.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 2 * unit),
            blur: 4 * unit,
            color: UIColor.black.withAlphaComponent(0.32).cgColor
        )
        context.setFillColor(UIColor(DSPalette.Red.r400).cgColor)
        context.fillEllipse(in: circle)
        context.restoreGState()
        if showsScanStartSelection {
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(3 * unit)
            context.strokeEllipse(in: circle.insetBy(dx: -4 * unit, dy: -4 * unit))
        }
    }

    private func checkpointMarker(_ checkpoint: LocalScanCheckpointMarker,
                                  unit: CGFloat, context: CGContext) {
        let position = cg(checkpoint.point)
        let diameter = (checkpointAppearance == .plain ? 32 : 34) * unit
        let circle = CGRect(
            x: position.x - diameter / 2,
            y: position.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 2 * unit),
            blur: 4 * unit,
            color: UIColor.black.withAlphaComponent(0.32).cgColor
        )
        if checkpointAppearance == .plain {
            let asset = checkpoint.state == .planned
                ? "InstructorScanCheckpointPlanned"
                : "InstructorScanCheckpoint"
            UIImage(named: asset)?.draw(in: circle)
            context.restoreGState()
            drawCheckpointState(checkpoint.state, in: circle, unit: unit, context: context)
            return
        }
        let fillColor: UIColor = checkpoint.state == .completed
            ? UIColor.systemBlue.withAlphaComponent(0.45)
            : .systemBlue
        context.setFillColor(fillColor.cgColor)
        context.fillEllipse(in: circle)
        context.restoreGState()
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2 * unit)
        context.strokeEllipse(in: circle.insetBy(dx: unit, dy: unit))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let label = checkpoint.state == .completed ? "✓" : String(checkpoint.number)
        let font = UIFont.boldSystemFont(ofSize: 16 * unit)
        (label as NSString).draw(
            in: CGRect(x: circle.minX, y: position.y - font.lineHeight / 2,
                       width: circle.width, height: font.lineHeight),
            withAttributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawCheckpointState(_ state: LocalScanCheckpointState,
                                     in circle: CGRect, unit: CGFloat, context: CGContext) {
        switch state {
        case .planned:
            return
        case .selected:
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(3 * unit)
            context.strokeEllipse(in: circle.insetBy(dx: -4 * unit, dy: -4 * unit))
        case .completed:
            return
        }
    }
}
