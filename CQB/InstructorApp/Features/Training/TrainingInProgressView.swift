import CQBDesignSystem
import SwiftUI

struct TrainingInProgressView: View {
    @Environment(InstructorStore.self) private var store
    @State private var isShowingFinishConfirmation = false

    var body: some View {
        ZStack {
            DSColor.backgroundPrimary
                .ignoresSafeArea()

            trainingTimer

            VStack(spacing: 0) {
                header

                Spacer()

                statusContent
            }
            .padding(DSSpacing.s40)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("훈련을 종료하시겠습니까?", isPresented: $isShowingFinishConfirmation) {
            Button("확인", action: store.finishTraining)
            Button("취소", role: .cancel) {}
        } message: {
            Text("훈련이 종료되면 AAR 화면으로 넘어갑니다.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("훈련 기록 중")
                .dsTextStyle(DSTypography.headingBold36)
                .foregroundStyle(DSColor.contentPrimary)

            Spacer()

            Button {
                isShowingFinishConfirmation = true
            } label: {
                Text(finishButtonTitle)
                    .dsTextStyle(DSTypography.headingBold20)
                    .frame(width: 180, height: 55)
            }
            .buttonStyle(TrainingFinishButtonStyle())
            .disabled(!store.canFinishTraining)
            .accessibilityIdentifier("training.finish")
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var trainingTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = store.trainingElapsed(at: context.date)
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

    @ViewBuilder
    private var statusContent: some View {
        VStack(spacing: DSSpacing.s16) {
            if store.phase == .resultsPreparation {
                resultsPreparationStatus
            } else if let error = store.trainingActionError {
                Text(error)
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(DSColor.statusError)
                    .accessibilityIdentifier("training.finishError")
            }

            if store.sessionConnectionState == .connecting {
                ProgressView("서버 훈련 정보 연결 중…")
                    .tint(DSColor.contentPrimary)
                    .foregroundStyle(DSColor.contentSecondary)
            } else if let error = store.sessionObservationError {
                HStack(spacing: DSSpacing.s16) {
                    Text(error)
                        .dsTextStyle(DSTypography.bodyRegular16)

                    Button("다시 연결", action: store.retrySessionObservation)
                        .buttonStyle(.dsSecondary)
                        .disabled(!store.canRetrySessionObservation)
                        .accessibilityIdentifier("training.reconnect")
                }
                .foregroundStyle(DSColor.contentSecondary)
            }
        }
    }

    @ViewBuilder
    private var resultsPreparationStatus: some View {
        if store.trainingRecords.connectionState == .failed,
           let error = store.trainingRecords.errorMessage {
            HStack(spacing: DSSpacing.s16) {
                Text(error)
                    .dsTextStyle(DSTypography.bodyRegular16)

                Button("다시 연결", action: store.retryRecordingObservation)
                    .buttonStyle(.dsSecondary)
                    .disabled(!store.trainingRecords.canRetry)
                    .accessibilityIdentifier("results.reconnect")
            }
            .foregroundStyle(DSColor.contentSecondary)
        } else {
            ProgressView("AAR 준비 중…")
                .tint(DSColor.contentPrimary)
                .foregroundStyle(DSColor.contentSecondary)
                .accessibilityIdentifier("results.preparing")
        }
    }

    private var finishButtonTitle: String {
        if store.phase == .resultsPreparation { return "AAR 준비 중…" }
        return store.isFinishingTraining ? "훈련 종료 중…" : "훈련 종료"
    }
}

private struct TrainingFinishButtonStyle: ButtonStyle {
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

#Preview("훈련 중") {
    TrainingInProgressView()
        .environment(InstructorStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
