import SwiftUI

struct TrainingInProgressView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(store.trainingName)
                .font(.title2)
            Text(store.sampleTrainingElapsed)
                .font(.system(size: 64, weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel("샘플 경과 시간 \(store.sampleTrainingElapsed)")
            Text("고정된 샘플 시간 · 실제 타이머는 동작하지 않습니다")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                ActionButton("훈련 종료", action: store.finishTraining)
                    .accessibilityIdentifier("training.finish")
            }
            .padding(24)
            .background(.bar)
        }
    }
}

#Preview {
    TrainingInProgressView()
        .environment(InstructorStore())
}
