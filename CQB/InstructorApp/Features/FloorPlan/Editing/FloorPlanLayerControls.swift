import CQBDesignSystem
import SwiftUI

struct FloorPlanLayerControls: View {
    @Binding var display: FloorPlanLayerDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            FloorPlanLabeledSlider(
                label: "원본 도면 투명도",
                value: $display.planOpacity
            )
            .accessibilityIdentifier("floorPlan.layers.planOpacity")

            FloorPlanLabeledSlider(
                label: "벽 레이어 투명도",
                value: $display.maskOpacity
            )
            .accessibilityIdentifier("floorPlan.layers.maskOpacity")

            HStack {
                Text("벽 마스크 표시")
                    .font(DSTypography.body)
                    .foregroundStyle(InstructorColor.textPrimary)
                Spacer()
                Toggle("", isOn: $display.showsMask)
                    .labelsHidden()
                    .tint(InstructorColor.actionPrimary)
                    .accessibilityLabel("벽 마스크 표시")
                    .accessibilityIdentifier("floorPlan.layers.maskVisible")
            }
            .frame(height: 28)
        }
        .accessibilityIdentifier("floorPlan.layers")
    }
}

struct FloorPlanLabeledSlider: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step = 0.05
    var formattedValue: (Double) -> String = { "\(Int($0 * 100))%" }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(label)
                Spacer()
                Text(formattedValue(value))
            }
            .font(DSTypography.body)
            .foregroundStyle(InstructorColor.textPrimary)

            Slider(value: $value, in: range, step: step)
                .tint(InstructorColor.actionPrimary)
                .accessibilityLabel(label)
        }
        .frame(height: 64)
    }
}
