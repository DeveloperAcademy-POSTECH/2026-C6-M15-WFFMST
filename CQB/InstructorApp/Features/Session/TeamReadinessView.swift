import SwiftUI

struct TeamReadinessView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Text("PIN · \(store.invitationCode)")
            Text("준비 상태 \(store.readyCount)/\(store.participants.count)")
            ActionButton("훈련 시작", action: store.startTraining).disabled(!store.canStartTraining)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

