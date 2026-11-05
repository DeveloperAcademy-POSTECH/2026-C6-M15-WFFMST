import CQBDesignSystem
import SwiftUI

/// InstructorApp 도면 편집의 선택 가능한 pill 외형입니다.
struct InstructorSelectablePillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsTextStyle(DSTypography.headingSemiBold20)
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
