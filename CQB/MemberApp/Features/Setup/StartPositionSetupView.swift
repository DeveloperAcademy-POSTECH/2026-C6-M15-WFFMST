import SwiftUI
import CQBDesignSystem

struct StartPositionSetupView: View {
    /// 실제 세션의 도면을 주입한다. 선택 좌표는 이미지 영역 기준 0...1이다.
    let floorPlan: UIImage
    var onConfirm: (CGPoint, CGPoint) -> Void
    @State private var startPoint: CGPoint?
    @State private var directionPoint: CGPoint?

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
                    .font(DSTypography.body2)
                    .foregroundStyle(DSColor.darkGreen)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                VStack(spacing: 24) {
                    statusRow("출발 위치", value: startPoint == nil ? "미지정" : "지정됨", isSet: startPoint != nil)
                    statusRow("바라보는 방향", value: directionPoint == nil ? "미설정" : "설정됨", isSet: directionPoint != nil)
                }
                .padding(.top, 20)
                Button("좌표 고정") {
                    if let startPoint, let directionPoint { onConfirm(startPoint, directionPoint) }
                }
                .buttonStyle(MemberPrimaryButtonStyle())
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
                        .font(DSTypography.etc.weight(.bold))
                        .foregroundStyle(DSColor.background)
                        .frame(width: 22, height: 22)
                        .background(DSColor.main, in: Circle())
                        .position(start)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                let point = CGPoint(x: (location.x - origin.x) / imageSize.width, y: (location.y - origin.y) / imageSize.height)
                guard (0...1).contains(point.x), (0...1).contains(point.y) else { return }
                if startPoint == nil || directionPoint != nil {
                    startPoint = point
                    directionPoint = nil
                } else if let startPoint, hypot(point.x - startPoint.x, point.y - startPoint.y) > 0.001 {
                    directionPoint = point
                }
            }
            .accessibilityLabel("출발 위치와 방향을 선택하는 훈련 도면")
            .accessibilityHint("출발 위치, 방향 순서로 터치합니다. 두 점 선택 후 다시 터치하면 재설정합니다.")
        }
        .aspectRatio(330.0 / 400.0, contentMode: .fit)
        .padding(12)
        .memberSurface()
    }

    private func statusRow(_ title: String, value: String, isSet: Bool) -> some View {
        HStack {
            Text(title).font(DSTypography.body1)
            Spacer()
            Text(value).font(DSTypography.body2)
                .foregroundStyle(isSet ? DSColor.main : DSColor.darkGreen)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .memberSurface()
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
