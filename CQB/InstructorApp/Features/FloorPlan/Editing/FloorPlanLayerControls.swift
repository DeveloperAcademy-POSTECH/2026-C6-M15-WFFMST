import CQBDesignSystem
import SwiftUI

struct FloorPlanLayerControls: View {
    @Binding var display: FloorPlanLayerDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            FloorPlanLabeledSlider(
                label: "원본 도면 투명도",
                value: planTransparency
            )
            .accessibilityIdentifier("floorPlan.layers.planTransparency")

            HStack {
                Text("벽 마스크 표시")
                    .dsTextStyle(DSTypography.bodyRegular16)
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

    private var planTransparency: Binding<Double> {
        Binding(
            get: { 1 - display.planOpacity },
            set: { display.planOpacity = 1 - $0 }
        )
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
            .dsTextStyle(DSTypography.bodyRegular16)
            .foregroundStyle(InstructorColor.textPrimary)

            Slider(value: $value, in: range, step: step)
                .tint(InstructorColor.actionPrimary)
                .accessibilityLabel(label)
        }
        .frame(height: 64)
    }
}
