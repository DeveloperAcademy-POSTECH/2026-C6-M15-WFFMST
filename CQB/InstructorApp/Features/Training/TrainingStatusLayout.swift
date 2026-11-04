import CQBDesignSystem
import SwiftUI

/// 훈련 중과 AAR 준비 중 화면이 공유하는 시각 구조다.
/// 시간 갱신 정책은 각 화면이 결정하고 이 레이아웃은 전달받은 값을 표시하기만 한다.
struct TrainingStatusLayout<HeaderAction: View, StatusContent: View>: View {
    let elapsed: String?
    private let headerAction: HeaderAction
    private let statusContent: StatusContent

    init(
        elapsed: String?,
        @ViewBuilder headerAction: () -> HeaderAction,
        @ViewBuilder statusContent: () -> StatusContent
    ) {
        self.elapsed = elapsed
        self.headerAction = headerAction()
        self.statusContent = statusContent()
    }

    var body: some View {
        ZStack {
            DSColor.backgroundPrimary
                .ignoresSafeArea()

            TrainingElapsedDisplay(elapsed: elapsed)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Text("훈련 기록 중")
                        .dsTextStyle(DSTypography.headingBold36)
                        .foregroundStyle(DSColor.contentPrimary)

                    Spacer()
                    headerAction
                }
                .frame(maxWidth: .infinity, alignment: .top)

                Spacer()
                statusContent
            }
            .padding(DSSpacing.s40)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct TrainingElapsedDisplay: View {
    let elapsed: String?

    var body: some View {
        HStack(spacing: DSSpacing.s32) {
            Circle()
                .fill(InstructorColor.trainingRecordingIndicator)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text(elapsed ?? "--:--")
                .dsTextStyle(DSTypography.headingBold36)
                .foregroundStyle(DSColor.contentPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(elapsed.map { "훈련 경과 시간 \($0)" } ?? "서버 시작 시각 확인 중")
        .accessibilityIdentifier("training.elapsed")
    }
}

struct TrainingFinishButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? DSColor.contentInverse : DSColor.contentDisabled)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .contentShape(Capsule())
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return DSColor.actionPrimaryDisabled }
        return isPressed ? DSColor.actionPrimaryPressed : DSColor.actionPrimary
    }
}
