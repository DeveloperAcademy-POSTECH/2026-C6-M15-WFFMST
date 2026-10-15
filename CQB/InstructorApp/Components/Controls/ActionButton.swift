import CQBDesignSystem
import SwiftUI

enum InstructorButtonTone: Equatable {
    case primary, secondary
}

enum InstructorButtonDensity: Equatable {
    case standard, compact, file

    var height: CGFloat {
        switch self {
        case .standard: 48
        case .compact: 44
        case .file: 36
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .standard: 320
        case .compact: 240
        case .file: 144
        }
    }

    var font: Font {
        DSFonts.register()
        return switch self {
        case .standard: Font.custom("NotoSansKR-Medium", size: 16, relativeTo: .body)
        case .compact: Font.custom("NotoSansKR-Medium", size: 12, relativeTo: .caption)
        case .file: Font.custom("NotoSansKR-Medium", size: 14, relativeTo: .body)
        }
    }
}

// 앱 상태와 업무 규칙을 받지 않는 InstructorApp 전용 action adapter.
struct ActionButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    var tone: InstructorButtonTone
    var density: InstructorButtonDensity
    var fillsWidth: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil,
         tone: InstructorButtonTone = .primary, density: InstructorButtonDensity = .standard,
         fillsWidth: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.tone = tone
        self.density = density
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(density.font)
            .frame(minWidth: 120, idealWidth: density.idealWidth,
                   maxWidth: fillsWidth ? .infinity : nil, minHeight: density.height)
            .contentShape(.rect)
        }
        .buttonStyle(InstructorActionButtonStyle(tone: tone))
    }
}

private struct InstructorActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let tone: InstructorButtonTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .background(backgroundColor)
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        guard isEnabled else { return InstructorColor.textSecondary }
        return tone == .primary ? InstructorColor.canvas : InstructorColor.textPrimary
    }

    private var backgroundColor: Color {
        guard isEnabled else { return InstructorColor.actionDisabled }
        return tone == .primary ? InstructorColor.actionPrimary : InstructorColor.surfaceRaised
    }

    private var borderColor: Color {
        guard isEnabled else { return InstructorColor.borderDefault }
        return tone == .primary ? InstructorColor.actionPrimary : InstructorColor.borderDefault
    }
}
