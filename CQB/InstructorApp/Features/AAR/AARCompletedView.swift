import CQBDesignSystem
import SwiftUI

struct AARCompletedView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        ZStack {
            Text("AAR 종료")
                .font(completionFont)
                .foregroundStyle(InstructorColor.textPrimary)
                .frame(minWidth: 270, minHeight: 80)
                .accessibilityAddTraits(.isHeader)

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    ActionButton(
                        "처음으로",
                        tone: .secondary,
                        fillsWidth: true,
                        action: store.returnHome
                    )
                    .frame(width: 300, height: 48)
                    .accessibilityIdentifier("aar.home")
                }
            }
            .padding(.trailing, 40)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var completionFont: Font {
        DSFonts.register()
        return .custom("NotoSansKR-Bold", size: 64, relativeTo: .largeTitle)
    }
}

#Preview("AAR 종료") {
    AARCompletedView()
        .environment(InstructorStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
