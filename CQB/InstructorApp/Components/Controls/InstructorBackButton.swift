import SwiftUI

/// InstructorApp 화면에서 공통으로 사용하는 44×44 뒤로가기 버튼입니다.
///
/// 화면 이동 규칙은 알지 않고 호출하는 화면이 전달한 action만 실행합니다.
struct InstructorBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("InstructorBackIcon")
                .renderingMode(.original)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityLabel("뒤로")
        .accessibilityIdentifier("navigation.back")
    }
}
