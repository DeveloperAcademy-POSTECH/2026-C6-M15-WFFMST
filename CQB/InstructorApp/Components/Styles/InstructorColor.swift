import CQBDesignSystem
import SwiftUI

/// InstructorApp에서 사용하는 Figma semantic color 역할과 실제 색상 토큰의 연결 지점입니다.
///
/// 공통 Package의 원시 토큰은 여기서 역할 이름으로 변환해 사용하고,
/// Package에 없는 색상만 InstructorApp의 Asset Catalog에서 가져옵니다.
enum InstructorColor {
    // MARK: - Surfaces

    /// Figma: `color/canvas`
    static let canvas = DSColor.background

    /// Figma: `color/surface/base`
    static let surfaceBase = DSColor.area1

    /// Figma: `color/surface/raised`
    static let surfaceRaised = DSColor.area2

    // MARK: - Actions and borders

    /// Figma: `color/action/primary`
    static let actionPrimary = DSColor.main

    /// Figma: `color/action/disabled`
    static let actionDisabled = Color("InstructorActionDisabled")

    /// Figma: `color/border/default`
    static let borderDefault = DSColor.area3

    // MARK: - Content

    /// Figma: `color/text/primary`
    static let textPrimary = DSColor.white

    /// Figma: `color/text/secondary`
    static let textSecondary = DSColor.darkGreen

    /// Figma: `color/icon/check`
    static let iconCheck = DSColor.white

    /// Apple semantic red used for validation and error feedback.
    static let validationError = Color.red

    // MARK: - Menus

    /// Figma: `color/menu/surface`
    static let menuSurface = DSColor.area3

    /// Figma: `color/menu/border`
    static let menuBorder = DSColor.area2

    // MARK: - Teams

    static let teamOne = DSColor.team1
    static let teamTwo = DSColor.team2
    static let teamThree = DSColor.team3

    // MARK: - Player

    /// Figma: `color/player/surface`
    static let playerSurface = DSColor.black

    /// Figma: `color/player/play`
    static let playerPlay = Color("InstructorPlayerPlay")
}
