import SwiftUI

public struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let disabledBackground: Color

    public init(disabledBackground: Color = DSColor.actionPrimaryDisabled) {
        self.disabledBackground = disabledBackground
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSTypography.headingSemiBold20.font)
            .lineSpacing(10)
            .foregroundStyle(isEnabled ? DSColor.contentInverse : DSColor.contentDisabled)
            .padding(.horizontal, DSSpacing.s20)
            .frame(minHeight: DSSize.actionButtonHeight)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(.rect(cornerRadius: DSRadius.full))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.full)
                    .stroke(isEnabled ? DSColor.borderEmphasized : .clear, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: DSRadius.full))
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return disabledBackground }
        return isPressed ? DSColor.actionPrimaryPressed : DSColor.actionPrimary
    }
}

public struct DSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSTypography.headingSemiBold20.font)
            .lineSpacing(10)
            .foregroundStyle(isEnabled ? DSColor.contentPrimary : DSColor.contentDisabled)
            .padding(.horizontal, DSSpacing.s20)
            .frame(minHeight: DSSize.actionButtonHeight)
            .background(isEnabled ? DSColor.actionSecondary : DSColor.actionDisabled)
            .clipShape(.rect(cornerRadius: DSRadius.full))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.rect(cornerRadius: DSRadius.full))
    }
}

public enum DSCircularButtonSize: CaseIterable, Sendable {
    case regular
    case compact

    public var dimension: CGFloat {
        switch self {
        case .regular:
            DSSize.controlHeight
        case .compact:
            DSSize.compactControlHeight
        }
    }
}

public struct DSCircularButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    private let size: DSCircularButtonSize
    private let showsBorder: Bool

    public init(size: DSCircularButtonSize = .regular, showsBorder: Bool = false) {
        self.size = size
        self.showsBorder = showsBorder
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? DSColor.contentPrimary : DSColor.contentDisabled)
            .frame(width: size.dimension, height: size.dimension)
            .background(DSColor.surfacePrimary)
            .clipShape(Circle())
            .overlay {
                if showsBorder { Circle().strokeBorder(DSColor.borderPrimary, lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(Circle())
            .dsButtonShadow()
    }
}

public extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }

    static func dsPrimary(disabledBackground: Color) -> DSPrimaryButtonStyle {
        DSPrimaryButtonStyle(disabledBackground: disabledBackground)
    }
}

public extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { DSSecondaryButtonStyle() }
}

public extension ButtonStyle where Self == DSCircularButtonStyle {
    static var dsCircular: DSCircularButtonStyle { DSCircularButtonStyle() }

    static func dsCircular(size: DSCircularButtonSize, showsBorder: Bool = false) -> DSCircularButtonStyle {
        DSCircularButtonStyle(size: size, showsBorder: showsBorder)
    }
}
