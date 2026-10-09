import SwiftUI
import UIKit

/// Display-only settings; never included in the obstacle grid or registration snapshot.
struct FloorPlanLayerDisplay: Equatable {
    var planOpacity = 1.0
    var maskOpacity = 0.65
    var showsMask = true
    var tint: FloorPlanMaskTint = .purple
}

enum FloorPlanMaskTint: String, CaseIterable, Identifiable {
    case purple, cyan, black, red
    var id: String { rawValue }
    var title: String {
        switch self {
        case .purple: "보라"
        case .cyan: "청록"
        case .black: "검정"
        case .red: "빨강"
        }
    }
    var color: UIColor {
        switch self {
        case .purple: UIColor(red: 155.0 / 255, green: 65.0 / 255, blue: 220.0 / 255, alpha: 1)
        case .cyan: .systemTeal
        case .black: .black
        case .red: .systemRed
        }
    }
}

struct FloorPlanLayerControls: View {
    @Binding var display: FloorPlanLayerDisplay

    var body: some View {
        DisclosureGroup("레이어 표시 · 농도·색상") {
            VStack(alignment: .leading, spacing: 10) {
                Text("표시만 바꿉니다. 장애물 판정과 등록 데이터에는 영향을 주지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("장애물 표시", isOn: $display.showsMask)
                    .accessibilityIdentifier("floorPlan.layers.maskVisible")
                Text("원본 도면 농도 \(Int(display.planOpacity * 100))%")
                Slider(value: $display.planOpacity, in: 0...1, step: 0.05)
                    .accessibilityLabel("원본 도면 농도")
                Text("장애물 농도 \(Int(display.maskOpacity * 100))%")
                Slider(value: $display.maskOpacity, in: 0...1, step: 0.05)
                    .accessibilityLabel("장애물 농도")
                Picker("장애물 색", selection: $display.tint) {
                    ForEach(FloorPlanMaskTint.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    ActionButton("겹쳐 보기") {
                        display.planOpacity = 0.55; display.maskOpacity = 0.85; display.showsMask = true
                    }
                    ActionButton("마스크만") {
                        display.planOpacity = 0; display.maskOpacity = 1; display.showsMask = true
                    }
                    ActionButton("도면만") { display.planOpacity = 1; display.showsMask = false }
                }
                .font(.caption)
            }
            .padding(.top, 8)
        }
        .accessibilityIdentifier("floorPlan.layers")
    }
}
