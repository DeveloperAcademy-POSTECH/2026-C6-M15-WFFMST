import CQBDesignSystem
import SwiftUI

/// 앱의 안내 용도를 패키지 타입에 연결한다. 문구와 표시 여부는 호출부가 담당한다.
struct MemberGuidanceView: View {
    enum Presentation {
        case map
        case camera
    }

    let message: String
    let presentation: Presentation

    var body: some View {
        DSGuideToast(message, type: presentation == .map ? .compact : .card)
    }
}
