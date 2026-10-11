import CQBDesignSystem
import SwiftUI

struct HomeView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        HStack(spacing: 24) {
            HomeActionButton(
                title: "도면 정보 관리",
                tone: store.canOpenSessionCreation ? .secondary : .primary,
                accessibilityHint: "등록된 도면 목록으로 이동합니다.",
                accessibilityIdentifier: "home.floorPlans",
                action: store.openFloorPlanList
            )

            HomeActionButton(
                title: "훈련 세션 생성",
                tone: store.canOpenSessionCreation ? .primary : .secondary,
                accessibilityHint: store.canOpenSessionCreation
                    ? "새 훈련 세션을 만드는 화면으로 이동합니다."
                    : "도면을 등록한 후 사용할 수 있습니다.",
                accessibilityIdentifier: "home.createSession",
                action: store.openSessionCreation
            )
            .disabled(!store.canOpenSessionCreation)
        }
        .frame(maxWidth: 1_088)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct HomeActionButton: View {
    private static let titleFont: Font = {
        DSFonts.register()
        return .custom("NotoSansKR-Medium", size: 24)
    }()

    enum Tone {
        case primary
        case secondary

        var foregroundColor: Color {
            switch self {
            case .primary: InstructorColor.canvas
            case .secondary: InstructorColor.textPrimary
            }
        }

        var backgroundColor: Color {
            switch self {
            case .primary: InstructorColor.actionPrimary
            case .secondary: InstructorColor.surfaceRaised
            }
        }

        var borderColor: Color {
            switch self {
            case .primary: InstructorColor.actionPrimary
            case .secondary: InstructorColor.borderDefault
            }
        }
    }

    let title: String
    let tone: Tone
    let accessibilityHint: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Self.titleFont)
                .foregroundStyle(tone.foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(HomeActionButtonStyle(tone: tone))
        .frame(maxWidth: 532, minHeight: 300, maxHeight: 300)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

}

private struct HomeActionButtonStyle: ButtonStyle {
    let tone: HomeActionButton.Tone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(tone.backgroundColor)
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(tone.borderColor, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("등록된 도면 없음") {
    NavigationStack {
        HomeView()
            .environment(InstructorStore(floorPlans: []))
    }
    .frame(width: 1_366, height: 1_024)
    .preferredColorScheme(.dark)
}

#Preview("등록된 도면 있음") {
    NavigationStack {
        HomeView()
            .environment(InstructorStore(floorPlans: [
                DemoFloorPlan(
                    id: "preview-plan",
                    name: "훈련장 A",
                    fileName: "훈련장 A 도면.png",
                    referenceDistance: 15
                )
            ]))
    }
    .frame(width: 1_366, height: 1_024)
    .preferredColorScheme(.dark)
}
