import CQBDesignSystem
import SwiftUI

enum InstructorButtonTone: Equatable {
    case primary, secondary
}

// 앱 상태와 업무 규칙을 받지 않는 InstructorApp 전용 action adapter.
struct ActionButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    var tone: InstructorButtonTone
    var fillsWidth: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil,
         tone: InstructorButtonTone = .primary, fillsWidth: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.tone = tone
        self.fillsWidth = fillsWidth
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if tone == .primary {
            button.buttonStyle(.dsPrimary)
        } else {
            button.buttonStyle(.dsSecondary)
        }
    }

    private var button: some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(minWidth: 140, maxWidth: fillsWidth ? .infinity : nil)
            .contentShape(.rect(cornerRadius: DSRadius.full))
        }
    }
}
