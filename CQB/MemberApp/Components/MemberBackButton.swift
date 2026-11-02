import CQBDesignSystem
import SwiftUI

struct MemberBackButton: View {
    /// 호출부에서 현재 흐름의 상태 정리와 복귀 동작을 주입한다.
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Image("MemberBackIcon")
                .renderingMode(.original)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .dsButtonShadow()
        .disabled(action == nil)
        .accessibilityLabel("뒤로 가기")
        .accessibilityHint(action == nil ? "현재 화면에서는 뒤로 갈 수 없습니다." : "이전 화면으로 돌아갑니다.")
    }
}
