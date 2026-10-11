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
                prompt: Text(placeholder).foregroundStyle(DSColor.darkGreen)
            )
            .font(DSTypography.body)
            .foregroundStyle(DSColor.white)
            .tint(DSColor.main)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(DSColor.area1)
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 1)
            }
            .accessibilityLabel(title)

            if let validationMessage {
                Text(validationMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var borderColor: Color {
        validationMessage == nil ? DSColor.area3 : .red
    }
}
