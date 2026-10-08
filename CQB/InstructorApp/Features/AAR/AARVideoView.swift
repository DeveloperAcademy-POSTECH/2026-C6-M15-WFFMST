import SwiftUI

struct AARVideoView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Text("영상 placeholder · \(store.selectedParticipants.count)명")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

