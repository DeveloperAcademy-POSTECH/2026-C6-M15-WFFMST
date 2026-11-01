import SwiftUI

public extension View {
    /// Figma `Shadow/Button`: 0 4 24, #848484 25%.
    func dsButtonShadow() -> some View {
        shadow(
            color: Color(red: 132.0 / 255.0, green: 132.0 / 255.0, blue: 132.0 / 255.0).opacity(0.25),
            radius: 24,
            y: 4
        )
    }

    /// Figma `Shadow/Floating`: 0 4 10, #000000 25%.
    func dsFloatingShadow() -> some View {
        shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
    }
}
