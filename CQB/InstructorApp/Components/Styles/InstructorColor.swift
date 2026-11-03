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

    /// Figma: `Liquid Glass - Regular - Medium`의 불투명 기본 면(#1A1A1A).
    static let savingOverlaySurface = Color("InstructorSavingOverlaySurface")

    // MARK: - Actions and borders

    /// Figma: `color/action/primary`
    static let actionPrimary = DSColor.main

    /// Figma: `color/action/disabled`
    static let actionDisabled = Color("InstructorActionDisabled")

    /// Figma: `color/border/default`
    static let borderDefault = DSColor.area3

    /// 도면 목록의 미선택 indicator와 미리보기 action border에 쓰는 Figma Gray/200.
    static let floorPlanSelectionIdle = DSPalette.Gray.g200
    static let floorPlanPreviewActionBorder = DSPalette.Gray.g200

    // MARK: - Content

    /// Figma: `color/text/primary`
    static let textPrimary = DSColor.white

    /// Figma: `color/text/secondary`
    static let textSecondary = DSColor.darkGreen

    /// Figma: `color/icon/check`
    static let iconCheck = DSColor.white

    /// Apple semantic red used for validation and error feedback.
    static let validationError = Color.red

    /// 훈련 중 화면의 녹화 상태 표시점에 쓰는 Figma Red/400.
    static let trainingRecordingIndicator = DSPalette.Red.r400

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

    // MARK: - AAR

    static let aarCanvas = DSColor.backgroundPrimary
    static let aarSurfaceRaised = DSColor.backgroundElevated
    static let aarActionPrimary = DSColor.actionPrimary
    static let aarActionDisabled = DSColor.actionPrimaryDisabled
    static let aarBorder = DSColor.borderPrimary
    static let aarContentPrimary = DSColor.contentPrimary
    static let aarContentSecondary = DSColor.contentSecondary
    static let aarPlayerSurface = DSPalette.Gray.g900
    static let aarMapSurface = DSPalette.Gray.g800
    static let aarVideoSlotSurface = DSPalette.Gray.g700
    static let aarPanelLabel = DSPalette.Gray.g200
    static let aarPlaceholderText = DSPalette.Gray.g400
    static let aarParticipantMarker = DSPalette.Gray.g600
    static let aarFloorPlanOverlay = DSPalette.Gray.g700.opacity(0.2)
    static let aarTimelineTrack = Color(
        red: 77.0 / 255.0,
        green: 77.0 / 255.0,
        blue: 77.0 / 255.0
    )
    static let aarTimelineProgress = DSPalette.Primary.p300

    // MARK: - Floor plan preview

    /// Figma: preview image overlay, `#747474` at 20% opacity.
    static let floorPlanPreviewOverlay = Color(
        red: 116.0 / 255.0,
        green: 116.0 / 255.0,
        blue: 116.0 / 255.0
    ).opacity(0.2)
}
