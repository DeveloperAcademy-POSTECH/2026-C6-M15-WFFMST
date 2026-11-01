import SwiftUI

public enum DSStatusBadgeTone {
    case neutral
    case success
    case warning
    case error
    case info

    fileprivate var background: Color {
        switch self {
        case .neutral: DSColor.surfacePrimary
        case .success: DSPalette.Green.g800
        case .warning: DSPalette.Yellow.y800
        case .error: DSPalette.Red.r800
        case .info: DSPalette.Blue.b800
        }
    }

    fileprivate var foreground: Color {
        switch self {
        case .neutral: DSColor.contentPrimary
        case .success: DSPalette.Green.g50
        case .warning: DSPalette.Yellow.y50
        case .error: DSPalette.Red.r50
        case .info: DSPalette.Blue.b50
        }
    }
}

public struct DSStatusBadge: View {
    private let title: String
    private let tone: DSStatusBadgeTone

    public init(_ title: String, tone: DSStatusBadgeTone = .neutral) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        Text(title)
            .dsTextStyle(DSTypography.bodyRegular12)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, DSSpacing.s8)
            .padding(.vertical, DSSpacing.s4)
            .background(tone.background)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.small))
    }
}
