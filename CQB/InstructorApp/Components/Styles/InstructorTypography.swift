import CQBDesignSystem
import SwiftUI

enum InstructorTypography {
    static let bodyMedium20 = DSTextStyle(
        postScriptName: "AppleSDGothicNeo-Medium",
        font: .custom("AppleSDGothicNeo-Medium", size: 20, relativeTo: .body),
        size: 20,
        lineHeight: 21
    )

    static let captionRegular13 = DSTextStyle(
        postScriptName: "AppleSDGothicNeo-Regular",
        font: .custom("AppleSDGothicNeo-Regular", size: 13, relativeTo: .caption),
        size: 13,
        lineHeight: 20
    )
}
