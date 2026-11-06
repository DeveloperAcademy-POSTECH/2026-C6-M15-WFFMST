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

/// 화면 맞춤 상태를 1배로 삼아 도면과 대원 좌표에 같은 확대·이동을 적용한다.
nonisolated struct AARFloorPlanViewport: Equatable, Sendable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4
    static let participantNameScale: CGFloat = 1.5
    static let identity = AARFloorPlanViewport()

    let scale: CGFloat
    let translation: CGSize

    init(scale: CGFloat = minimumScale, translation: CGSize = .zero) {
        self.scale = min(max(scale, Self.minimumScale), Self.maximumScale)
        self.translation = translation
    }

    var showsParticipantNames: Bool { scale >= Self.participantNameScale }

    /// 진행 중인 핀치·드래그 값을 반영하고 도면이 화면 밖으로 완전히 밀리지 않도록 제한한다.
    func applying(
        magnification: CGFloat = 1,
        anchor: CGPoint? = nil,
        drag: CGSize = .zero,
        layout: AARFloorPlanLayout,
        container: CGSize
    ) -> AARFloorPlanViewport {
        let nextScale = min(
            max(scale * magnification, Self.minimumScale),
            Self.maximumScale
        )
        let scaleRatio = nextScale / scale
        let center = CGPoint(x: layout.imageFrame.midX, y: layout.imageFrame.midY)
        let anchoredTranslation: CGSize
        if let anchor {
            anchoredTranslation = CGSize(
                width: translation.width
                    + (anchor.x - center.x - translation.width) * (1 - scaleRatio),
                height: translation.height
                    + (anchor.y - center.y - translation.height) * (1 - scaleRatio)
            )
        } else {
            anchoredTranslation = translation
        }
        let proposed = AARFloorPlanViewport(
            scale: nextScale,
            translation: CGSize(
                width: anchoredTranslation.width + drag.width,
                height: anchoredTranslation.height + drag.height
            )
        )
        return proposed.clamped(layout: layout, container: container)
    }

    func clamped(
        layout: AARFloorPlanLayout,
        container: CGSize
    ) -> AARFloorPlanViewport {
        let horizontalLimit = max((layout.imageFrame.width * scale - container.width) / 2, 0)
        let verticalLimit = max((layout.imageFrame.height * scale - container.height) / 2, 0)
        return AARFloorPlanViewport(
            scale: scale,
            translation: CGSize(
                width: min(max(translation.width, -horizontalLimit), horizontalLimit),
                height: min(max(translation.height, -verticalLimit), verticalLimit)
            )
        )
    }

    /// 도면 이미지 픽셀 좌표 → 확대·이동된 화면 좌표.
    /// 마커 자체는 확대하지 않고 이 좌표에 배치해 화면상 크기를 일정하게 유지한다.
    func viewPoint(
        for point: ImagePoint,
        layout: AARFloorPlanLayout
    ) -> CGPoint {
        let fittedPoint = layout.viewPoint(for: point)
        let center = CGPoint(x: layout.imageFrame.midX, y: layout.imageFrame.midY)
        return CGPoint(
            x: center.x + (fittedPoint.x - center.x) * scale + translation.width,
            y: center.y + (fittedPoint.y - center.y) * scale + translation.height
        )
    }
}
