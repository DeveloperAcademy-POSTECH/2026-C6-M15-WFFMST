import SwiftUI

struct TrainingInProgressView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Text(store.sampleTrainingElapsed)
            Text("샘플 시간")
            ActionButton("훈련 종료", action: store.finishTraining)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

