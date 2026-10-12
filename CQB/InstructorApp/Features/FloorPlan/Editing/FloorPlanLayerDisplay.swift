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
