import SwiftUI
import CQBDesignSystem

struct StartPositionSetupView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// 실제 세션의 도면을 주입한다. 선택 좌표는 이미지 영역 기준 0...1이다.
    let floorPlan: UIImage
    var onConfirm: (CGPoint, CGPoint) -> Void
    let onBack: (() -> Void)?
    @State private var startPoint: CGPoint?
    @State private var directionPoint: CGPoint?
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero

    init(floorPlan: UIImage, startPoint: CGPoint? = nil, directionPoint: CGPoint? = nil,
         onBack: (() -> Void)? = nil,
         onConfirm: @escaping (CGPoint, CGPoint) -> Void) {
        self.floorPlan = floorPlan
        self.onConfirm = onConfirm
        self.onBack = onBack
        _startPoint = State(initialValue: startPoint)
        _directionPoint = State(initialValue: directionPoint)
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var guidance: String {
        startPoint == nil
            ? "도면을 터치해 본인의 출발 위치를 선택해주세요."
            : "선택한 위치에서\n바라보는 방향을 터치하여 방향을 설정해주세요."
    }

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = isLandscape ? geometry.size.height : min(240, geometry.size.height / 2)
            let layout = isLandscape
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            layout {
                map
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        MemberBackButton(action: onBack)
                            .padding(DSSpacing.s20)
                    }
                    .overlay(alignment: isLandscape ? .top : .bottom) {
                        if startPoint == nil || directionPoint == nil {
                            MemberGuidanceView(message: guidance, presentation: .map)
                                .frame(maxWidth: isLandscape ? 366 : .infinity)
                                .padding(.horizontal, isLandscape ? DSSpacing.s60 + DSSpacing.s20 : DSSpacing.s20)
                                .padding(.vertical, isLandscape ? DSSpacing.s20 : DSSpacing.s12)
                        }
                    }

                settingsPanel(height: panelHeight)
                    .frame(width: isLandscape ? min(280, geometry.size.width * 0.4) : nil,
                           height: panelHeight)
            }
        }
        // 가로에서는 화면 전체 폭을 기준으로 도면과 우측 패널을 배치한다.
        .ignoresSafeArea(.container, edges: isLandscape ? .horizontal : [])
        .foregroundStyle(DSColor.contentPrimary)
        .background(DSColor.surfaceSecondary.ignoresSafeArea())
    }

    private func settingsPanel(height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.s20) {
                if !isLandscape {
                    Text("출발 위치 설정")
                        .dsTextStyle(DSTypography.headingBold20)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(spacing: DSSpacing.s4) {
                    SetupStatusRow("출발 위치", value: startPoint == nil ? "지정 안 됨" : "지정됨")
                    SetupStatusRow("바라보는 방향", value: directionPoint == nil ? "설정 전" : "설정됨")
                }
                Spacer(minLength: 0)
                ActionButton("훈련 시작") {
                    if let startPoint, let directionPoint { onConfirm(startPoint, directionPoint) }
                }
                .disabled(startPoint == nil || directionPoint == nil)
                .accessibilityHint("출발 위치와 방향을 고정하고 지휘관의 시작 신호를 기다립니다.")
                .accessibilityIdentifier("setup.confirm")
            }
            .frame(minHeight: max(0, height - DSSpacing.s40), alignment: .topLeading)
            .padding(DSSpacing.s20)
        }
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: DSRadius.large,
                bottomLeadingRadius: isLandscape ? DSRadius.large : 0,
                topTrailingRadius: isLandscape ? 0 : DSRadius.large
            )
            .fill(DSColor.surfacePrimary)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var map: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = min(size.width / floorPlan.size.width, size.height / floorPlan.size.height)
            let imageSize = CGSize(width: floorPlan.size.width * scale, height: floorPlan.size.height * scale)
            let origin = CGPoint(x: (size.width - imageSize.width) / 2, y: (size.height - imageSize.height) / 2)
            let effectiveZoom = min(max(zoomScale * pinchScale, 1), 4)
            let effectiveOffset = clampedOffset(
                CGSize(width: zoomOffset.width + dragTranslation.width,
                       height: zoomOffset.height + dragTranslation.height),
                zoom: effectiveZoom,
                size: size
            )
            ZStack {
                Image(uiImage: floorPlan)
                    .resizable().scaledToFit().opacity(0.6)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(effectiveZoom)
                    .offset(effectiveOffset)

                if let startPoint {
                    // 두 선택점은 도면의 확대·이동을 따르고 원의 크기와 방향 마커의 폭은 유지한다.
                    let baseStart = CGPoint(x: origin.x + startPoint.x * imageSize.width,
                                            y: origin.y + startPoint.y * imageSize.height)
                    let start = CGPoint(
                        x: (baseStart.x - size.width / 2) * effectiveZoom + size.width / 2 + effectiveOffset.width,
                        y: (baseStart.y - size.height / 2) * effectiveZoom + size.height / 2 + effectiveOffset.height
                    )
                    if let directionPoint {
                        let baseEnd = CGPoint(x: origin.x + directionPoint.x * imageSize.width,
                                              y: origin.y + directionPoint.y * imageSize.height)
                        let end = CGPoint(
                            x: (baseEnd.x - size.width / 2) * effectiveZoom + size.width / 2 + effectiveOffset.width,
                            y: (baseEnd.y - size.height / 2) * effectiveZoom + size.height / 2 + effectiveOffset.height
                        )
                        // 방향 표시는 사용자의 선택 좌표로 생성되는 동적 도형이다.
                        Path { path in
                            let angle = atan2(end.y - start.y, end.x - start.x)
                            let perpendicular = CGPoint(x: -sin(angle) * 9.5, y: cos(angle) * 9.5)
                            path.move(to: start)
                            path.addLine(to: CGPoint(x: end.x + perpendicular.x, y: end.y + perpendicular.y))
                            path.addLine(to: CGPoint(x: end.x - perpendicular.x, y: end.y - perpendicular.y))
                            path.closeSubpath()
                        }
                        .fill(DSPalette.Blue.b300)
                    }
                    Circle()
                        .fill(DSPalette.Blue.b500)
                        .frame(width: 22, height: 22)
                        .overlay { Circle().strokeBorder(DSPalette.Neutral.white, lineWidth: 2) }
                        .position(start)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                let baseLocation = CGPoint(
                    x: (location.x - size.width / 2 - effectiveOffset.width) / effectiveZoom + size.width / 2,
                    y: (location.y - size.height / 2 - effectiveOffset.height) / effectiveZoom + size.height / 2
                )
                let point = CGPoint(x: (baseLocation.x - origin.x) / imageSize.width,
                                    y: (baseLocation.y - origin.y) / imageSize.height)
                guard (0...1).contains(point.x), (0...1).contains(point.y) else { return }
                if startPoint == nil || directionPoint != nil {
                    startPoint = point
                    directionPoint = nil
                } else if let startPoint, hypot(point.x - startPoint.x, point.y - startPoint.y) > 0.001 {
                    directionPoint = point
                }
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinchScale) { value, state, _ in state = value }
                    .onEnded { value in
                        zoomScale = min(max(zoomScale * value, 1), 4)
                        if zoomScale == 1 { zoomOffset = .zero }
                    }
            )
            .highPriorityGesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in
                        guard zoomScale > 1 else { return }
                        state = value.translation
                    }
                    .onEnded { value in
                        guard zoomScale > 1 else { return }
                        zoomOffset = clampedOffset(
                            CGSize(width: zoomOffset.width + value.translation.width,
                                   height: zoomOffset.height + value.translation.height),
                            zoom: zoomScale,
                            size: size
                        )
                    },
                including: zoomScale > 1 ? .gesture : .none
            )
            .accessibilityLabel("출발 위치와 방향을 선택하는 훈련 도면")
            .accessibilityHint("두 손가락으로 확대하고 확대된 도면은 드래그할 수 있습니다. 출발 위치, 방향 순서로 터치합니다. 두 점 선택 후 다시 터치하면 재설정합니다.")
        }
        .clipped()
        .background(DSColor.surfaceSecondary)
        .accessibilityIdentifier("setup.map")
    }

    private func clampedOffset(_ offset: CGSize, zoom: CGFloat, size: CGSize) -> CGSize {
        let maxX = size.width * (zoom - 1) / 2
        let maxY = size.height * (zoom - 1) / 2
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }
}

#Preview("위치 지정 전") {
    if let image = UIImage(named: "TrainingFloorPlan") {
        StartPositionSetupView(floorPlan: image) { start, direction in
            print("Preview 좌표: \(start), \(direction)")
        }
    }
}

#Preview("위치·방향 지정 완료") {
    if let image = UIImage(named: "TrainingFloorPlan") {
        StartPositionSetupView(floorPlan: image, startPoint: CGPoint(x: 0.512, y: 0.84),
                               directionPoint: CGPoint(x: 0.512, y: 0.73)) { _, _ in
            print("Preview 좌표 고정")
        }
    }
}

#Preview("02 위치·방향 설정 · 가로", traits: .landscapeLeft) {
    if let image = UIImage(named: "TrainingFloorPlan") {
        StartPositionSetupView(floorPlan: image, startPoint: CGPoint(x: 0.512, y: 0.84),
                               directionPoint: CGPoint(x: 0.512, y: 0.73)) { _, _ in
            print("Preview 좌표 고정")
        }
    }
}

#Preview("02 위치 설정 · 큰 글자") {
    if let image = UIImage(named: "TrainingFloorPlan") {
        StartPositionSetupView(floorPlan: image) { _, _ in print("Preview 좌표 고정") }
            .dynamicTypeSize(.accessibility3)
    }
}
