import SwiftUI

public enum DSGuideToastType: CaseIterable, Sendable {
    case regular
    case compact
    case card
}

/// 앱 도메인과 상태에 의존하지 않는 범용 안내 컴포넌트입니다.
/// `onDismiss`를 전달하면 X 버튼을 표시하며, 실제 표시 여부는 호출부가 관리합니다.
public struct DSGuideToast: View {
    private let message: String
    private let type: DSGuideToastType
    private let systemImage: String
    private let horizontalPadding: CGFloat?
    private let fillsWidth: Bool
    private let onDismiss: (() -> Void)?
    private let dismissAccessibilityIdentifier: String

    public init(
        _ message: String,
        type: DSGuideToastType = .regular,
        systemImage: String = "info.circle",
        horizontalPadding: CGFloat? = nil,
        fillsWidth: Bool = false,
        onDismiss: (() -> Void)? = nil,
        dismissAccessibilityIdentifier: String = "guideToast.dismiss"
    ) {
        self.message = message
        self.type = type
        self.systemImage = systemImage
        self.horizontalPadding = horizontalPadding
        self.fillsWidth = fillsWidth
        self.onDismiss = onDismiss
        self.dismissAccessibilityIdentifier = dismissAccessibilityIdentifier
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
        .accessibilityElement(children: onDismiss == nil ? .combine : .contain)
    }

    private var regularToast: some View {
        HStack(spacing: DSSpacing.s20) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .accessibilityHidden(true)

            Text(message)
                .dsTextStyle(DSTypography.headingSemiBold20)
                .fixedSize(horizontal: false, vertical: onDismiss != nil)
                .frame(maxWidth: .infinity, alignment: .leading)

            dismissButton
        }
        .foregroundStyle(DSColor.contentPrimary)
        .padding(.horizontal, horizontalPadding ?? DSSpacing.s32)
        .padding(.vertical, onDismiss == nil ? 0 : DSSpacing.s16)
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
        HStack(spacing: DSSpacing.s12) {
            Text(message)
                .dsTextStyle(DSTypography.captionRegular14)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: fillsWidth ? .infinity : nil)

            dismissButton
        }
        .foregroundStyle(DSColor.contentPrimary)
        .frame(minHeight: fillsWidth ? DSSpacing.s24 : nil)
        .padding(.horizontal, horizontalPadding ?? DSSpacing.s24)
        .padding(.vertical, DSSpacing.s12)
        .background(DSColor.surfacePrimary)
        .clipShape(Capsule())
    }

    private var cardToast: some View {
        HStack(spacing: DSSpacing.s12) {
            Text(message)
                .dsTextStyle(DSTypography.bodyRegular20)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            dismissButton
        }
        .foregroundStyle(DSColor.contentPrimary)
        .padding(.horizontal, horizontalPadding ?? DSSpacing.s20)
        .padding(.vertical, DSSpacing.s16)
        .background(DSColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
        .dsFloatingShadow()
    }

    @ViewBuilder
    private var dismissButton: some View {
        if let onDismiss {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: DSSize.compactControlHeight, height: DSSize.compactControlHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("안내 메시지 닫기")
            .accessibilityIdentifier(dismissAccessibilityIdentifier)
        }
    }
}

#Preview("안내 메시지 닫기") {
    @Previewable @State var isPresented = true

    VStack {
        if isPresented {
            DSGuideToast(
                "방의 입구나 모서리, 복도의 연결부 등 공간의 특징점이 될만한 지점을 터치해 표시해주세요.",
                onDismiss: { isPresented = false }
            )
        } else {
            Button("안내 다시 표시") { isPresented = true }
        }
    }
    .frame(width: 690)
    .padding()
}
