import SwiftUI

public struct DSFloatingBanner: View {
    private let title: String
    private let systemImage: String

    public init(_ title: String, systemImage: String = "info.circle") {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: DSSpacing.s20) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .accessibilityHidden(true)

            Text(title)
                .dsTextStyle(DSTypography.headingSemiBold20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(DSColor.contentPrimary)
        .padding(.horizontal, DSSpacing.s32)
        .frame(minHeight: 100)
        .background(DSColor.surfaceSecondary)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(DSColor.surfaceSelected, lineWidth: 1)
        }
        .dsFloatingShadow()
        .accessibilityElement(children: .combine)
    }
}
