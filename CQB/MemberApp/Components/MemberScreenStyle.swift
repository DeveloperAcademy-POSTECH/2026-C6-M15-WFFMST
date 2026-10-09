import SwiftUI
import CQBDesignSystem

/// MemberApp 화면에서 반복되는 Figma MVP 컨트롤 스타일.
struct MemberPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("NotoSansKR-Medium", size: 16, relativeTo: .body))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(isEnabled ? DSColor.background : DSColor.darkGreen)
            .background(isEnabled ? DSColor.main : Color("MemberActionDisabled"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isEnabled ? DSColor.main : DSColor.area3))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension View {
    func memberSurface() -> some View {
        background(DSColor.area1)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSColor.area3))
    }
}
