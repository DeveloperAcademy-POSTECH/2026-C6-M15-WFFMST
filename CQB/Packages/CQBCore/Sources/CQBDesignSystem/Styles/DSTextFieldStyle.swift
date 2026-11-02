import SwiftUI

public enum DSTextFieldAppearance: Sendable {
    case outlined
    case filled
}

public struct DSTextFieldStyle: TextFieldStyle {
    @Environment(\.isEnabled) private var isEnabled

    private let isFocused: Bool
    private let hasError: Bool
    private let appearance: DSTextFieldAppearance

    public init(isFocused: Bool = false, hasError: Bool = false,
                appearance: DSTextFieldAppearance = .outlined) {
        self.isFocused = isFocused
        self.hasError = hasError
        self.appearance = appearance
    }

    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(appearance == .filled ? DSTypography.bodyRegular16.font : DSTypography.headingSemiBold20.font)
            .lineSpacing(appearance == .filled ? 0 : 10)
            .foregroundStyle(isEnabled ? DSColor.contentPrimary : DSColor.contentDisabled)
            .tint(DSColor.contentPrimary)
            .padding(.horizontal, appearance == .filled ? DSSpacing.s16 : DSSpacing.s20)
            .frame(minHeight: DSSize.controlHeight)
            .background(DSColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.medium)
                    .stroke(borderColor, lineWidth: appearance == .filled && !hasError ? 0 : (isFocused || hasError ? 2 : 1))
            }
            .opacity(isEnabled ? 1 : 0.65)
    }

    private var borderColor: Color {
        if hasError { return DSColor.statusError }
        if isFocused { return DSColor.contentPrimary }
        return DSColor.borderPrimary
    }
}

public extension TextFieldStyle where Self == DSTextFieldStyle {
    static var dsDefault: DSTextFieldStyle { DSTextFieldStyle() }

    static func ds(isFocused: Bool, hasError: Bool = false,
                   appearance: DSTextFieldAppearance = .outlined) -> DSTextFieldStyle {
        DSTextFieldStyle(isFocused: isFocused, hasError: hasError, appearance: appearance)
    }
}
