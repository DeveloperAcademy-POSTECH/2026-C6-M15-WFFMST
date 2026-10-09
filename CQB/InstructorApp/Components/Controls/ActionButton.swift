import SwiftUI

// 디자인 적용 시 이 View의 내부만 교체한다. 앱 상태와 업무 규칙은 받지 않는다.
struct ActionButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            if let systemImage { Label(title, systemImage: systemImage) }
            else { Text(title) }
        }
    }
}
