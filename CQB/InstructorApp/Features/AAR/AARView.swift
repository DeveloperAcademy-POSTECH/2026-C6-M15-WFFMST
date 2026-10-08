import SwiftUI

struct AARView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            if store.aarMode == .movement { AARMovementView() } else { AARVideoView() }
            Toggle("대원 바디캠", isOn: Binding(get: { store.aarMode == .video },
                       set: { store.changeAARMode(to: $0 ? .video : .movement) }))
            ActionButton("AAR 종료", action: store.finishAAR)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

