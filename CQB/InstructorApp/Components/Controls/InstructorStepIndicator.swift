import CQBDesignSystem
import SwiftUI

/// InstructorApp 도면 생성 흐름의 현재 단계를 표시합니다.
struct InstructorStepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        Text("\(current) / \(total)")
            .dsTextStyle(DSTypography.bodyRegular16)
            .foregroundStyle(DSColor.contentPrimary)
            .monospacedDigit()
            .accessibilityLabel("전체 \(total)단계 중 \(current)단계")
    }
}
