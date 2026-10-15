import CQBDesignSystem
import SwiftUI

struct TrainingInProgressView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        ZStack {
            trainingTimer

            VStack(alignment: .leading, spacing: 0) {
                Text("훈련중")
                    .font(DSTypography.h1)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48,
                        maxHeight: 48,
                        alignment: .leading
                    )

                Spacer()

                if let error = store.trainingActionError {
                    Text(error)
                        .foregroundStyle(InstructorColor.textSecondary)
                        .accessibilityIdentifier("training.finishError")
                }
                if store.sessionConnectionState == .connecting {
                    ProgressView("서버 훈련 정보 연결 중…")
                } else if let error = store.sessionObservationError {
                    HStack {
                        Text(error)
                        Button("다시 연결", action: store.retrySessionObservation)
                            .disabled(!store.canRetrySessionObservation)
                            .accessibilityIdentifier("training.reconnect")
                    }
                    .foregroundStyle(InstructorColor.textSecondary)
                }

                HStack {
                    Spacer()
                    ActionButton(
                        store.isFinishingTraining ? "훈련 종료 중…" : "훈련 종료",
                        tone: .secondary,
                        fillsWidth: true,
                        action: store.finishTraining
                    )
                    .frame(width: 300, height: 48)
                    .disabled(!store.canFinishTraining)
                    .accessibilityIdentifier("training.finish")
                }
            }
            .padding(.top, 16)
            .padding(.leading, 48)
            .padding(.trailing, 40)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var trainingTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = store.trainingElapsed(at: context.date)
            HStack(spacing: 24) {
                Circle()
                    .fill(InstructorColor.teamOne)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)

                Text(elapsed ?? "시작 시각 확인 중…")
                    .font(displayFont)
                    .tracking(2.4)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(minWidth: 254, minHeight: 72)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(elapsed.map { "훈련 경과 시간 \($0)" } ?? "서버 시작 시각 확인 중")
            .accessibilityIdentifier("training.elapsed")
        }
    }

    private var displayFont: Font {
        DSFonts.register()
        return .custom("NotoSansKR-Bold", size: 48, relativeTo: .largeTitle)
    }
}

#Preview("훈련 중") {
    TrainingInProgressView()
        .environment(InstructorStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
