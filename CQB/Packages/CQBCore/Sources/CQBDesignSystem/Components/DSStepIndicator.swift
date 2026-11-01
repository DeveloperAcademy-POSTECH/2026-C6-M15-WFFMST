import SwiftUI

public struct DSStepIndicator: View {
    private let current: Int
    private let total: Int

    public init(current: Int, total: Int) {
        self.current = current
        self.total = total
    }

    public var body: some View {
        Text("\(current) / \(total)")
            .dsTextStyle(DSTypography.bodyRegular16)
            .foregroundStyle(DSColor.contentPrimary)
            .monospacedDigit()
            .accessibilityLabel("전체 \(total)단계 중 \(current)단계")
    }
}
