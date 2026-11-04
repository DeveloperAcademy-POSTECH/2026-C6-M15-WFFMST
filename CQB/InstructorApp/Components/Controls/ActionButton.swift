import CQBDesignSystem
import SwiftUI

enum InstructorButtonTone: Equatable {
    case primary, secondary
}

enum InstructorActionButtonWidth: Equatable {
    case content
    case fixed180
    case fill
}

// 앱 상태와 업무 규칙을 받지 않는 InstructorApp 전용 action adapter.
struct ActionButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    var tone: InstructorButtonTone
    var width: InstructorActionButtonWidth
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil,
         tone: InstructorButtonTone = .primary,
         width: InstructorActionButtonWidth = .content,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.tone = tone
        self.width = width
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        switch width {
        case .content:
            styledButton
        case .fixed180:
            styledButton
                .frame(width: 180, height: DSSize.actionButtonHeight)
        case .fill:
            styledButton
                .frame(maxWidth: .infinity, minHeight: DSSize.actionButtonHeight)
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
            .padding(.vertical, DSSpacing.s12)
            .frame(maxWidth: width == .content ? nil : .infinity)
            .contentShape(.rect(cornerRadius: DSRadius.full))
        }
    }

    @ViewBuilder
    private var styledButton: some View {
        if tone == .primary {
            button.buttonStyle(.dsPrimary)
        } else {
            button.buttonStyle(.dsSecondary)
        }
    }
}
