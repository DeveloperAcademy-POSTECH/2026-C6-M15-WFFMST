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

                HStack {
                    Spacer()
                    ActionButton(
                        "훈련 종료",
                        tone: .secondary,
                        fillsWidth: true,
                        action: store.finishTraining
                    )
                    .frame(width: 300, height: 48)
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
        HStack(spacing: 24) {
            Circle()
                .fill(InstructorColor.teamOne)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)

            Text(store.sampleTrainingElapsed)
                .font(displayFont)
                .tracking(2.4)
                .foregroundStyle(InstructorColor.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 254, minHeight: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("훈련 경과 시간 \(store.sampleTrainingElapsed)")
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
