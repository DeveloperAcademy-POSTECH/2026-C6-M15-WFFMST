import CoreGraphics
import CQBCore

/// AAR 화면에서 도면 이미지 픽셀 좌표를 화면 좌표로 바꾼다.
/// 도면은 화면 영역 안에서 여백을 뺀 뒤 비율을 유지해 가운데에 맞춘다(`scaledToFit` + `padding`).
nonisolated struct AARFloorPlanLayout: Equatable, Sendable {
    /// 도면 이미지가 실제로 그려지는 화면 영역
    let imageFrame: CGRect
    let imageSize: CGSize

    init(imageSize: CGSize, container: CGSize, padding: CGFloat) {
        self.imageSize = imageSize
        let available = CGSize(
            width: max(container.width - padding * 2, 0),
            height: max(container.height - padding * 2, 0)
        )
        guard imageSize.width > 0, imageSize.height > 0 else {
            imageFrame = CGRect(x: padding, y: padding, width: 0, height: 0)
            return
        }
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        imageFrame = CGRect(
            x: (container.width - fitted.width) / 2,
            y: (container.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// 도면 이미지 픽셀 좌표 → 화면 좌표
    func viewPoint(for point: ImagePoint) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return imageFrame.origin }
        return CGPoint(
            x: imageFrame.minX + CGFloat(point.x) / imageSize.width * imageFrame.width,
            y: imageFrame.minY + CGFloat(point.y) / imageSize.height * imageFrame.height
        )
    }
}
