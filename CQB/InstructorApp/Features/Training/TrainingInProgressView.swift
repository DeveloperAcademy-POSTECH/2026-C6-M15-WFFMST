import CQBDesignSystem
import SwiftUI

struct TrainingInProgressView: View {
    @Environment(InstructorStore.self) private var store
    @State private var isShowingFinishConfirmation = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            TrainingStatusLayout(elapsed: store.trainingElapsed(at: context.date)) {
                finishButton
            } statusContent: {
                statusContent
            }
        }
        .alert("훈련을 종료하시겠습니까?", isPresented: $isShowingFinishConfirmation) {
            Button("확인", action: store.finishTraining)
            Button("취소", role: .cancel) {}
        } message: {
            Text("훈련이 종료되면 AAR 화면으로 넘어갑니다.")
        }
    }

    private var finishButton: some View {
        Button {
            isShowingFinishConfirmation = true
        } label: {
            Text(store.isFinishingTraining ? "훈련 종료 중…" : "훈련 종료")
                .dsTextStyle(DSTypography.headingBold20)
                .frame(width: 180, height: 55)
        }
        .buttonStyle(TrainingFinishButtonStyle())
        .disabled(!store.canFinishTraining)
        .accessibilityIdentifier("training.finish")
    }

    @ViewBuilder
    private var statusContent: some View {
        VStack(spacing: DSSpacing.s16) {
            if let error = store.trainingActionError {
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
}

#Preview("훈련 중") {
    TrainingInProgressView()
        .environment(InstructorStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
