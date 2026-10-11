import CQBDesignSystem
import SwiftUI

// 앱 상태와 업무 규칙을 받지 않는 InstructorApp 전용 action adapter.
struct ActionButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(DSTypography.body)
            .frame(minWidth: 120, idealWidth: 320, minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(InstructorPrimaryButtonStyle())
    }
}

private struct InstructorPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? DSColor.background : DSColor.darkGreen)
            .padding(.horizontal, 12)
            .background(isEnabled ? DSColor.main : InstructorControlColor.actionDisabled)
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isEnabled ? DSColor.main : DSColor.area3, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
