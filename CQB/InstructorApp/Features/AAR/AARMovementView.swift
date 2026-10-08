import SwiftUI

struct AARMovementView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Text("샘플 동선 · \(store.selectedParticipants.count)명")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

