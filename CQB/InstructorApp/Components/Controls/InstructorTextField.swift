import CQBDesignSystem
import SwiftUI

struct InstructorTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                placeholder,
                text: $text,
                prompt: Text(placeholder).foregroundStyle(InstructorColor.textSecondary)
            )
            .font(DSTypography.body)
            .foregroundStyle(InstructorColor.textPrimary)
            .tint(InstructorColor.actionPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(InstructorColor.surfaceBase)
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 1)
            }
            .accessibilityLabel(title)

            if let validationMessage {
                Text(validationMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(InstructorColor.validationError)
            }
        }
    }

    private var borderColor: Color {
        validationMessage == nil ? InstructorColor.borderDefault : InstructorColor.validationError
    }
}
