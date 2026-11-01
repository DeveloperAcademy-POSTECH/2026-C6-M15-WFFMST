import SwiftUI

/// SwiftUI `Slider`의 interaction과 접근성을 유지하면서 Figma track과 thumb를 표시합니다.
public struct DSStyledSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double.Stride
    private let accessibilityLabel: String
    private let accessibilityValue: String

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...1,
        step: Double.Stride = 0.01,
        accessibilityLabel: String,
        accessibilityValue: String
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }

    public var body: some View {
        GeometryReader { proxy in
            let thumbDiameter: CGFloat = 20
            let trackWidth = max(0, proxy.size.width - thumbDiameter)
            let progress = normalizedValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DSColor.surfaceSelected)
                    .frame(width: trackWidth, height: 4)
                    .offset(x: thumbDiameter / 2)

                Capsule()
                    .fill(DSColor.contentPrimary)
                    .frame(width: max(2, trackWidth * progress), height: 4)
                    .offset(x: thumbDiameter / 2)

                Circle()
                    .fill(DSColor.contentPrimary)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: trackWidth * progress)

                Slider(value: $value, in: range, step: step)
                    .opacity(0.001)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(accessibilityValue)
            }
        }
        .frame(height: 28)
    }

    private var normalizedValue: CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(min(max(fraction, 0), 1))
    }
}

public struct DSLabeledSlider: View {
    private let title: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double.Stride
    private let formatValue: (Double) -> String

    public init(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...1,
        step: Double.Stride = 0.01,
        formatValue: @escaping (Double) -> String = { "\(Int($0 * 100))%" }
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.formatValue = formatValue
    }

    public var body: some View {
        VStack(spacing: DSSpacing.s8) {
            HStack {
                Text(title)
                Spacer()
                Text(formatValue(value))
                    .monospacedDigit()
            }
            .dsTextStyle(DSTypography.bodyRegular16)
            .foregroundStyle(DSColor.contentPrimary)

            DSStyledSlider(
                value: $value,
                in: range,
                step: step,
                accessibilityLabel: title,
                accessibilityValue: formatValue(value)
            )
        }
    }
}
