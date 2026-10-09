import SwiftUI
import CQBDesignSystem

struct ActionButton: View {
    private let title: String
    private let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(ActionButtonStyle())
    }
}

private struct ActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSTypography.body1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(isEnabled ? DSColor.background : DSColor.darkGreen)
            .background(isEnabled ? DSColor.main : Color("MemberActionDisabled"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isEnabled ? DSColor.main : DSColor.area3))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}


#Preview("Active Button") {
    VStack(spacing: 24) {
        ActionButton("참가") { print("Preview 참가") }
        ActionButton("홈으로") { print("Preview 홈 이동") }
            .disabled(true)
    }
    .padding(24)
    .background(DSColor.background)
}
