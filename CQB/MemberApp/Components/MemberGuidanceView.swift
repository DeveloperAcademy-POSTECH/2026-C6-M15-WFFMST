import CQBDesignSystem
import SwiftUI

/// 도면 조작 안내와 카메라 상태 안내의 MemberApp 표현. 상태 판단은 호출부가 담당한다.
struct MemberGuidanceView: View {
    enum Presentation {
        case map
        case camera
    }

    let message: String
    let presentation: Presentation

    var body: some View {
        Text(message)
            .dsTextStyle(presentation == .map ? DSTypography.captionRegular14 : DSTypography.bodyRegular20)
            .multilineTextAlignment(presentation == .map ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, presentation == .map ? DSSpacing.s24 : DSSpacing.s20)
            .padding(.vertical, presentation == .map ? DSSpacing.s12 : DSSpacing.s16)
            .foregroundStyle(DSColor.contentPrimary)
            .background(presentation == .map ? DSColor.surfacePrimary : DSColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: presentation == .map ? DSRadius.full : DSRadius.large))
            .dsFloatingShadow()
    }
}
