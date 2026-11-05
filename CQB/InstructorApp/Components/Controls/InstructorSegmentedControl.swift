import CQBDesignSystem
import SwiftUI

/// InstructorApp 도면 편집 도구를 전환하는 segmented control입니다.
struct InstructorSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option

                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .dsTextStyle(DSTypography.bodyRegular16)
                        .foregroundStyle(DSColor.contentPrimary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(isSelected ? DSColor.surfaceSelected : .clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(DSSpacing.s4)
        .frame(minHeight: 40)
        .background(DSColor.surfaceSecondary)
        .clipShape(Capsule())
    }
}
