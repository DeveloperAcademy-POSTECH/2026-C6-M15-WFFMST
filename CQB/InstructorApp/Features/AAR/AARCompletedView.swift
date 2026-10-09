import SwiftUI

struct AARCompletedView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Text("AAR 종료").font(.largeTitle.bold())
                Text("화면 연결 데모를 완료했습니다.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Spacer()
                ActionButton("처음으로", systemImage: "house", action: store.returnHome)
                    .accessibilityIdentifier("aar.home")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AARCompletedView().environment(InstructorStore())
}
