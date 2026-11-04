import CQBDesignSystem
import SwiftUI

/// Instructor 홈의 훈련 시작 CTA 전용 규격입니다.
/// 일반 action button과 달리 고정 크기와 전용 타이포를 사용합니다.
struct HomeTrainingStartButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button("훈련 시작하기", action: action)
            .buttonStyle(HomeTrainingStartButtonStyle())
            .frame(width: 311, height: DSSize.controlHeight)
            .disabled(!isEnabled)
    }
}

private struct HomeTrainingStartButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsTextStyle(DSTypography.headingExtraBold24)
            .foregroundStyle(isEnabled ? DSPalette.Primary.p800 : DSColor.contentDisabled)
            .padding(.horizontal, DSSpacing.s20)
            .padding(.vertical, DSSpacing.s12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(.capsule)
            .contentShape(.capsule)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return DSColor.actionPrimaryDisabled }
        return isPressed ? DSColor.actionPrimaryPressed : DSPalette.Primary.p500
    }
}
