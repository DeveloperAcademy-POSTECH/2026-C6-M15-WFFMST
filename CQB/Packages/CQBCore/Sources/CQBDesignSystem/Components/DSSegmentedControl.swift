import SwiftUI

public struct DSSegmentedControl<Option: Hashable>: View {
    private let options: [Option]
    @Binding private var selection: Option
    private let title: (Option) -> String

    public init(
        options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> String
    ) {
        self.options = options
        self._selection = selection
        self.title = title
    }

    public var body: some View {
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
