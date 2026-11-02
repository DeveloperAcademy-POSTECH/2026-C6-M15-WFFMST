import CQBDesignSystem
import SwiftUI

/// 도면 관리 하이파이 화면에서 공통으로 사용하는 56×56 뒤로가기 버튼입니다.
struct FloorPlanBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("FloorPlanBackIcon")
                .renderingMode(.original)
                .resizable()
                .frame(width: DSSize.controlHeight, height: DSSize.controlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .dsButtonShadow()
        .accessibilityLabel("뒤로")
        .accessibilityIdentifier("navigation.back")
    }
}
