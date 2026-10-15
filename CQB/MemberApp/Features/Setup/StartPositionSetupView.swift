import SwiftUI
import CQBDesignSystem

struct StartPositionSetupView: View {
    /// 실제 세션의 도면을 주입한다. 선택 좌표는 이미지 영역 기준 0...1이다.
    let floorPlan: UIImage
    var onConfirm: (CGPoint, CGPoint) -> Void
    @State private var startPoint: CGPoint?
    @State private var directionPoint: CGPoint?
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero

    init(floorPlan: UIImage, startPoint: CGPoint? = nil, directionPoint: CGPoint? = nil,
         onConfirm: @escaping (CGPoint, CGPoint) -> Void) {
        self.floorPlan = floorPlan
        self.onConfirm = onConfirm
        _startPoint = State(initialValue: startPoint)
        _directionPoint = State(initialValue: directionPoint)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("도면 좌표 보정").font(DSTypography.h2)
                map
                Text(startPoint == nil
                     ? "도면 위 터치를 통해 본인의 출발위치를 선택해주세요."
                     : "이후 선택한 위치에서 바라보는 방향을 한번 더 터치하여 방향을 설정해주세요.")
                    .font(DSTypography.bodySmall)
                    .foregroundStyle(DSColor.darkGreen)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                VStack(spacing: 24) {
                    SetupStatusRow("출발 위치", value: startPoint == nil ? "미지정" : "지정됨", isSet: startPoint != nil)
                    SetupStatusRow("바라보는 방향", value: directionPoint == nil ? "미설정" : "설정됨", isSet: directionPoint != nil)
                }
                .padding(.top, 20)
                ActionButton("좌표 고정") {
                    if let startPoint, let directionPoint { onConfirm(startPoint, directionPoint) }
                }
                .disabled(startPoint == nil || directionPoint == nil)
                .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .foregroundStyle(DSColor.white)
        .background(DSColor.background.ignoresSafeArea())
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
                ZStack {
                    Image(uiImage: floorPlan)
                        .resizable().scaledToFit().opacity(0.6)
                    if let startPoint {
                        let start = CGPoint(x: origin.x + startPoint.x * imageSize.width, y: origin.y + startPoint.y * imageSize.height)
                        if let directionPoint {
                            let end = CGPoint(x: origin.x + directionPoint.x * imageSize.width, y: origin.y + directionPoint.y * imageSize.height)
                            // 방향 표시는 사용자의 선택 좌표로 생성되는 동적 도형이다.
                            Path { path in
                                let angle = atan2(end.y - start.y, end.x - start.x)
                                let perpendicular = CGPoint(x: -sin(angle) * 9.5, y: cos(angle) * 9.5)
                                path.move(to: start)
                                path.addLine(to: CGPoint(x: end.x + perpendicular.x, y: end.y + perpendicular.y))
                                path.addLine(to: CGPoint(x: end.x - perpendicular.x, y: end.y - perpendicular.y))
                                path.closeSubpath()
                            }
                            .fill(DSColor.main)
                        }
                        Text("1")
                            .font(DSTypography.caption.weight(.bold))
                            .foregroundStyle(DSColor.background)
                            .frame(width: 22, height: 22)
                            .background(DSColor.main, in: Circle())
                            .position(start)
                    }
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(effectiveZoom)
                .offset(effectiveOffset)
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
        .aspectRatio(floorPlan.size.width / floorPlan.size.height, contentMode: .fit)
        .padding(12)
        .background(DSColor.area1)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSColor.area3))
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
