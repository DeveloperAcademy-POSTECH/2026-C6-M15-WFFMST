import SwiftUI

public enum DSGuideToastType: CaseIterable, Sendable {
    case regular
    case compact
    case card
}

/// 앱 도메인과 상태에 의존하지 않는 범용 안내 컴포넌트입니다.
public struct DSGuideToast: View {
    private let message: String
    private let type: DSGuideToastType
    private let systemImage: String

    public init(
        _ message: String,
        type: DSGuideToastType = .regular,
        systemImage: String = "info.circle"
    ) {
        self.message = message
        self.type = type
        self.systemImage = systemImage
    }

    public var body: some View {
        Group {
            switch type {
            case .regular:
                regularToast
            case .compact:
                compactToast
            case .card:
                cardToast
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var regularToast: some View {
        HStack(spacing: DSSpacing.s20) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .accessibilityHidden(true)

            Text(message)
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
    }

    private var compactToast: some View {
        Text(message)
            .dsTextStyle(DSTypography.captionRegular14)
            .foregroundStyle(DSColor.contentPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DSSpacing.s24)
            .padding(.vertical, DSSpacing.s12)
            .background(DSColor.surfacePrimary)
            .clipShape(Capsule())
    }

    private var cardToast: some View {
        Text(message)
            .dsTextStyle(DSTypography.bodyRegular20)
            .foregroundStyle(DSColor.contentPrimary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.s20)
            .padding(.vertical, DSSpacing.s16)
            .background(DSColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
            .dsFloatingShadow()
    }
}
