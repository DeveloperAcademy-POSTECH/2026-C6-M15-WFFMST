import SwiftUI

public extension View {
    /// Figma `Shadow/Button`: blur 24, y 4, #848484 25%.
    ///
    /// Figma의 blur 24는 SwiftUI export에서 `radius: 12`로 변환됩니다.
    func dsButtonShadow() -> some View {
        shadow(
            color: Color(red: 0.52, green: 0.52, blue: 0.52).opacity(0.25),
            radius: 12,
            y: 4
        )
    }

    /// Figma `Shadow/Floating`: 0 4 24, #000000 25%.
    func dsFloatingShadow() -> some View {
        shadow(color: Color.black.opacity(0.25), radius: 24, y: 4)
    }
}
