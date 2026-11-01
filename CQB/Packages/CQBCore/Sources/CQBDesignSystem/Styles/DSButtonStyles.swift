import SwiftUI

public struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSTypography.headingSemiBold20.font)
            .lineSpacing(10)
            .foregroundStyle(isEnabled ? DSColor.contentInverse : DSColor.contentDisabled)
            .padding(.horizontal, DSSpacing.s20)
            .frame(minHeight: DSSize.controlHeight)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isEnabled ? DSColor.borderEmphasized : .clear, lineWidth: 1)
            }
            .contentShape(Capsule())
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return DSColor.actionDisabled }
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
            .frame(minHeight: DSSize.controlHeight)
            .background(isEnabled ? DSColor.actionSecondary : DSColor.actionDisabled)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

public struct DSCircularButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? DSColor.contentPrimary : DSColor.contentDisabled)
            .frame(width: DSSize.controlHeight, height: DSSize.controlHeight)
            .background(DSColor.surfacePrimary)
            .clipShape(Circle())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(Circle())
            .dsButtonShadow()
    }
}

public struct DSSelectablePillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    private let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSTypography.headingSemiBold20.font)
            .lineSpacing(10)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, DSSpacing.s20)
            .frame(minHeight: 45)
            .background(isSelected ? DSPalette.Primary.p300 : .clear)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(DSPalette.Primary.p100, lineWidth: isSelected ? 1 : 2)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(Capsule())
    }

    private var foregroundColor: Color {
        guard isEnabled else { return DSColor.contentDisabled }
        return isSelected ? DSPalette.Primary.p900 : DSPalette.Primary.p50
    }
}

public extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

public extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { DSSecondaryButtonStyle() }
}

public extension ButtonStyle where Self == DSCircularButtonStyle {
    static var dsCircular: DSCircularButtonStyle { DSCircularButtonStyle() }
}
