import CQBDesignSystem
import Testing

@Test func spacingScaleMatchesFigma() {
    #expect([
        DSSpacing.s4,
        DSSpacing.s8,
        DSSpacing.s12,
        DSSpacing.s16,
        DSSpacing.s20,
        DSSpacing.s24,
        DSSpacing.s32,
        DSSpacing.s40,
        DSSpacing.s60,
    ] == [4, 8, 12, 16, 20, 24, 32, 40, 60])
}

@Test func radiusScaleMatchesFigma() {
    #expect(DSRadius.small == 8)
    #expect(DSRadius.medium == 12)
    #expect(DSRadius.large == 16)
    #expect(DSRadius.full == 999)
}

@Test func standardControlHeightMatchesFigma() {
    #expect(DSSize.controlHeight == 56)
    #expect(DSSize.compactControlHeight == 44)
    #expect(DSCircularButtonSize.regular.dimension == 56)
    #expect(DSCircularButtonSize.compact.dimension == 44)
}

@Test func guideToastTypesMatchFigma() {
    #expect(DSGuideToastType.allCases == [.regular, .compact, .card])
}

@Test func typographyMetadataMatchesFigma() {
    #expect(DSTypography.displayBold48.postScriptName == "AppleSDGothicNeo-Bold")
    #expect(DSTypography.displayBold48.size == 48)
    #expect(DSTypography.displayBold48.lineHeight == 48)
    #expect(DSTypography.headingSemiBold20.size == 20)
    #expect(DSTypography.headingSemiBold20.lineHeight == 30)
    #expect(DSTypography.captionRegular14.size == 14)
    #expect(DSTypography.captionRegular14.lineHeight == 21)
    #expect(DSTypography.headingExtraBold24.postScriptName == "AppleSDGothicNeo-ExtraBold")
}
