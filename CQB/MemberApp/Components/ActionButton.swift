import SwiftUI
import CQBDesignSystem

struct ActionButton: View {
    private let title: String
    private let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsPrimary)
    }
}


#Preview("Active Button") {
    VStack(spacing: DSSpacing.s24) {
        ActionButton("참가") { print("Preview 참가") }
        ActionButton("홈으로") { print("Preview 홈 이동") }
            .disabled(true)
    }
    .padding(DSSpacing.s24)
    .background(DSColor.backgroundPrimary)
}
