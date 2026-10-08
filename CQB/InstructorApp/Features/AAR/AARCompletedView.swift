import SwiftUI

struct AARCompletedView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Text("AAR 종료")
            ActionButton("처음으로", action: store.returnHome)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

