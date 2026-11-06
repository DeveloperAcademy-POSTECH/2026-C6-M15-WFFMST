import CQBDesignSystem
import SwiftUI

/// 기록 전송의 안내 문구·진행률·막대를 표시하는 MemberApp 컴포넌트.
struct UploadProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let progress: Double
    let isComplete: Bool
    var message = "전송 완료 전까지\n앱을 종료하지 않고 대기해주세요"

    private var displayedProgress: Double {
        if isComplete { return 1 }
        return progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    private var percentage: String {
        "\(Int(displayedProgress * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s12) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.s8))
                : AnyLayout(HStackLayout(alignment: .bottom, spacing: DSSpacing.s12))

            layout {
                Text(message)
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(percentage)
                    .dsTextStyle(DSTypography.bodyRegular20)
                    .monospacedDigit()
                    .fixedSize()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    DSPalette.Gray.g600
                    (isComplete ? DSPalette.Gray.g50 : DSPalette.Gray.g100)
                        .frame(width: max(0, geometry.size.width) * displayedProgress)
                        .animation(reduceMotion ? nil : .linear(duration: 0.05), value: displayedProgress)
                }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.full))
            }
            .frame(height: DSSpacing.s8)
        }
        .foregroundStyle(DSColor.contentPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("데이터 전송 진행률. \(message)")
        .accessibilityValue(percentage)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Upload Progress · Uploading") {
    UploadProgressView(progress: 0.8, isComplete: false)
        .padding(DSSpacing.s24)
        .background(DSColor.backgroundPrimary)
}

#Preview("Upload Progress · Done") {
    // 서버 저장 완료 시 입력 진행률과 무관하게 100%를 표시한다.
    UploadProgressView(progress: 0.8, isComplete: true)
        .padding(DSSpacing.s24)
        .background(DSColor.backgroundPrimary)
}

#Preview("Upload Progress · 긴 문구 · Dynamic Type") {
    UploadProgressView(
        progress: 0.8,
        isComplete: false,
        message: "훈련 기록을 서버로 전송하고 있습니다. 전송이 완료될 때까지 앱을 종료하지 않고 잠시 기다려주세요."
    )
    .padding(DSSpacing.s24)
    .background(DSColor.backgroundPrimary)
    .dynamicTypeSize(.accessibility3)
}
