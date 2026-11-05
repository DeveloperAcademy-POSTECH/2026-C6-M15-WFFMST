import CQBDesignSystem
import SwiftUI

/// InstructorApp 도면 편집용 Slider의 interaction과 접근성을 유지합니다.
struct InstructorStyledSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double.Stride
    let accessibilityLabel: String
    let accessibilityValue: String

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...1,
        step: Double.Stride = 0.01,
        accessibilityLabel: String,
        accessibilityValue: String
    ) {
        _value = value
        self.range = range
        self.step = step
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }

    var body: some View {
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
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(
                            at: gesture.location.x,
                            trackWidth: trackWidth,
                            thumbDiameter: thumbDiameter
                        )
                    }
            )
        }
        .frame(height: 28)
    }

    private func updateValue(at x: CGFloat, trackWidth: CGFloat, thumbDiameter: CGFloat) {
        guard trackWidth > 0, range.upperBound > range.lowerBound else { return }
        let progress = min(1, max(0, (x - thumbDiameter / 2) / trackWidth))
        let rawValue = range.lowerBound
            + Double(progress) * (range.upperBound - range.lowerBound)
        let steppedValue: Double
        if step > 0 {
            steppedValue = range.lowerBound
                + ((rawValue - range.lowerBound) / step).rounded() * step
        } else {
            steppedValue = rawValue
        }
        value = min(range.upperBound, max(range.lowerBound, steppedValue))
    }

    private var normalizedValue: CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(min(max(fraction, 0), 1))
    }
}

struct InstructorLabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double.Stride
    let formatValue: (Double) -> String

    init(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...1,
        step: Double.Stride = 0.01,
        formatValue: @escaping (Double) -> String = { "\(Int($0 * 100))%" }
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.formatValue = formatValue
    }

    var body: some View {
        VStack(spacing: DSSpacing.s8) {
            HStack {
                Text(title)
                Spacer()
                Text(formatValue(value))
                    .monospacedDigit()
            }
            .dsTextStyle(DSTypography.bodyRegular16)
            .foregroundStyle(DSColor.contentPrimary)

            InstructorStyledSlider(
                value: $value,
                in: range,
                step: step,
                accessibilityLabel: title,
                accessibilityValue: formatValue(value)
            )
        }
    }
}
