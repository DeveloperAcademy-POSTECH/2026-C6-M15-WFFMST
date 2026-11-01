import SwiftUI

/// Figma 텍스트 스타일의 폰트와 행간·자간을 함께 보존합니다.
public struct DSTextStyle: @unchecked Sendable {
    public let postScriptName: String
    public let font: Font
    public let size: CGFloat
    public let lineHeight: CGFloat?
    public let tracking: CGFloat

    public init(
        postScriptName: String,
        font: Font,
        size: CGFloat,
        lineHeight: CGFloat? = nil,
        tracking: CGFloat = 0
    ) {
        self.postScriptName = postScriptName
        self.font = font
        self.size = size
        self.lineHeight = lineHeight
        self.tracking = tracking
    }
}

public extension DSTypography {
    static let displayBold48 = textStyle(.bold, size: 48, relativeTo: .largeTitle, lineHeight: 48, tracking: 0.2857)
    static let displaySemiBold48 = textStyle(.semiBold, size: 48, relativeTo: .largeTitle, lineHeight: 60)
    static let displayBold40 = textStyle(.bold, size: 40, relativeTo: .largeTitle, lineHeight: 71, tracking: 2.5)

    static let headingBold36 = textStyle(.bold, size: 36, relativeTo: .largeTitle, tracking: 1.25)
    static let headingBold32 = textStyle(.bold, size: 32, relativeTo: .title)
    static let headingSemiBold32 = textStyle(.semiBold, size: 32, relativeTo: .title)
    static let headingSemiBold28 = textStyle(.semiBold, size: 28, relativeTo: .title)
    static let headingExtraBold24 = textStyle(.extraBold, size: 24, relativeTo: .title2)
    static let headingSemiBold24 = textStyle(.semiBold, size: 24, relativeTo: .title2)
    static let headingSemiBold20 = textStyle(.semiBold, size: 20, relativeTo: .title3, lineHeight: 30)
    static let headingBold20 = textStyle(.bold, size: 20, relativeTo: .title3, lineHeight: 30)

    static let bodyRegular24 = textStyle(.regular, size: 24, relativeTo: .body)
    static let bodyRegular20 = textStyle(.regular, size: 20, relativeTo: .body, lineHeight: 30)
    static let bodyRegular16 = textStyle(.regular, size: 16, relativeTo: .body)
    static let bodyRegular12 = textStyle(.regular, size: 12, relativeTo: .caption)
    static let captionMedium14 = textStyle(.medium, size: 14, relativeTo: .caption, lineHeight: 21)
    static let captionRegular14 = textStyle(.regular, size: 14, relativeTo: .caption, lineHeight: 21)

    private enum AppleSDGothicNeoWeight: String {
        case regular = "AppleSDGothicNeo-Regular"
        case medium = "AppleSDGothicNeo-Medium"
        case semiBold = "AppleSDGothicNeo-SemiBold"
        case bold = "AppleSDGothicNeo-Bold"
        case extraBold = "AppleSDGothicNeo-ExtraBold"
    }

    private static func textStyle(
        _ weight: AppleSDGothicNeoWeight,
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        lineHeight: CGFloat? = nil,
        tracking: CGFloat = 0
    ) -> DSTextStyle {
        DSTextStyle(
            postScriptName: weight.rawValue,
            font: .custom(weight.rawValue, size: size, relativeTo: textStyle),
            size: size,
            lineHeight: lineHeight,
            tracking: tracking
        )
    }
}

public extension View {
    @ViewBuilder
    func dsTextStyle(_ style: DSTextStyle) -> some View {
        if #available(macOS 13.0, *) {
            font(style.font)
                .tracking(style.tracking)
                .lineSpacing(max(0, (style.lineHeight ?? style.size) - style.size))
        } else {
            font(style.font)
                .lineSpacing(max(0, (style.lineHeight ?? style.size) - style.size))
        }
    }
}
