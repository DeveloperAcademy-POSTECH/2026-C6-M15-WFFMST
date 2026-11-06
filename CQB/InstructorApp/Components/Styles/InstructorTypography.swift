import CQBDesignSystem
import SwiftUI

enum InstructorTypography {
    static let displayBold64 = DSTextStyle(
        postScriptName: "AppleSDGothicNeo-Bold",
        font: .custom("AppleSDGothicNeo-Bold", size: 64, relativeTo: .largeTitle),
        size: 64
    )

    static let bodyMedium16 = DSTextStyle(
        postScriptName: "AppleSDGothicNeo-Medium",
        font: .custom("AppleSDGothicNeo-Medium", size: 16, relativeTo: .body),
        size: 16
    )

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

    static let captionBold14 = DSTextStyle(
        postScriptName: "AppleSDGothicNeo-Bold",
        font: .custom("AppleSDGothicNeo-Bold", size: 14, relativeTo: .caption),
        size: 14
    )
}
