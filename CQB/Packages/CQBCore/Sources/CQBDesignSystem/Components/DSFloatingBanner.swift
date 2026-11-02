import SwiftUI

public struct DSFloatingBanner: View {
    private let title: String
    private let systemImage: String

    public init(_ title: String, systemImage: String = "info.circle") {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        DSGuideToast(title, type: .regular, systemImage: systemImage)
    }
}
