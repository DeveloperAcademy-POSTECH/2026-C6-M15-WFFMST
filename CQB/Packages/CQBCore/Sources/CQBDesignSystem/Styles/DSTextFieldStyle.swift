import SwiftUI

public struct DSTextFieldStyle: TextFieldStyle {
    @Environment(\.isEnabled) private var isEnabled

    private let isFocused: Bool
    private let hasError: Bool

    public init(isFocused: Bool = false, hasError: Bool = false) {
        self.isFocused = isFocused
        self.hasError = hasError
    }

    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DSTypography.headingSemiBold20.font)
            .lineSpacing(10)
            .foregroundStyle(isEnabled ? DSColor.contentPrimary : DSColor.contentDisabled)
            .tint(DSColor.contentPrimary)
            .padding(.horizontal, DSSpacing.s20)
            .frame(minHeight: DSSize.controlHeight)
            .background(DSColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.medium)
                    .stroke(borderColor, lineWidth: isFocused || hasError ? 2 : 1)
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

    static func ds(isFocused: Bool, hasError: Bool = false) -> DSTextFieldStyle {
        DSTextFieldStyle(isFocused: isFocused, hasError: hasError)
    }
}
