import SwiftUI

struct AARContentView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        Group {
            if store.aarMode == .movement {
                AARMovementView()
            } else {
                AARVideoView()
            }
        }
    }
}
