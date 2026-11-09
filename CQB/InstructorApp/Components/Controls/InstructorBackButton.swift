import CQBDesignSystem
import SwiftUI

/// Figma `Map navigation`을 따르는 InstructorApp 공통 뒤로가기 버튼입니다.
///
/// 화면 이동 규칙은 알지 않고 호출하는 화면이 전달한 action만 실행합니다.
struct InstructorBackButton: View {
    private static let dimension: CGFloat = 55

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(DSPalette.Gray.g800)

                Image("InstructorBackIcon")
                    .renderingMode(.original)
                    .resizable()
                    .frame(width: Self.dimension, height: Self.dimension)
                    .offset(x: -1, y: -1)
            }
            .frame(width: Self.dimension, height: Self.dimension)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(DSPalette.Gray.g700, lineWidth: 1)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .dsButtonShadow()
        .accessibilityLabel("뒤로")
        .accessibilityIdentifier("navigation.back")
    }
}
