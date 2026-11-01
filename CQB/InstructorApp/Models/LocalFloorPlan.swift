import Foundation

// Issue #8: 앱 실행 중에만 사용하는 데이터. CQBCore/서버 직렬화 계약이 아니다.
nonisolated struct LocalPlanPoint: Equatable, Sendable {
    var x: Double
    var y: Double
    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

nonisolated enum LocalEditMode: Sendable { case block, open }

nonisolated struct LocalEditStroke: Equatable, Sendable {
    var mode: LocalEditMode
    var points: [LocalPlanPoint]
    var normalizedDiameter: Double
}

/// 펜툴로 지정한 다각형 내부를 한 번에 막거나 여는 편집입니다.
nonisolated struct LocalEditRegion: Equatable, Sendable {
    var mode: LocalEditMode
    var points: [LocalPlanPoint]
}

/// 브러시와 다각형 편집의 적용 순서를 보존하는 앱 내부 편집 이력입니다.
nonisolated enum LocalEditAction: Equatable, Sendable {
    case stroke(LocalEditStroke)
    case region(LocalEditRegion)
}

nonisolated struct LocalObstacleGrid: Equatable, Sendable {
    var columns: Int
    var rows: Int
    var cellSizePixels: Int
    var blocked: [UInt8]
}

nonisolated struct LocalPlanScale: Equatable, Sendable {
    var a: LocalPlanPoint
    var b: LocalPlanPoint
    var meters: Double
}

nonisolated struct LocalImportedImage: Equatable, Sendable {
    var pngData: Data
    var width: Int
    var height: Int
    var fileName: String
}

nonisolated enum LocalWallExtractionAlgorithm: String, Equatable, Sendable {
    case v13 = "v13-wall-detector"
    case binaryCoreML = "unet-resnet34-binary-fp16-v1"
}

nonisolated struct LocalExtractionResult: Sendable {
    var image: LocalImportedImage
    var baseGrid: LocalObstacleGrid
    var suggestedOutline: [LocalPlanPoint]
    var extractionAlgorithm: LocalWallExtractionAlgorithm = .v13
}

/// 정규화된 도면과 독립적으로 완료되는 벽·장애물 추출 결과다.
nonisolated struct LocalMaskExtractionResult: Sendable {
    var baseGrid: LocalObstacleGrid
    var suggestedOutline: [LocalPlanPoint]
    var extractionAlgorithm: LocalWallExtractionAlgorithm
}

nonisolated struct LocalBlockedRegionSuggestion: Equatable, Sendable {
    var outline: [LocalPlanPoint]
    var confidence: Double
    var closingRadiusCells: Int
}

nonisolated struct LocalRegisteredFloorPlan: Equatable, Sendable {
    let id: UUID
    let name: String
    let image: LocalImportedImage
    let baseGrid: LocalObstacleGrid
    let edits: [LocalEditAction]
    let outline: [LocalPlanPoint]
    let scale: LocalPlanScale
    let resolvedGrid: LocalObstacleGrid
    let extractionAlgorithm: LocalWallExtractionAlgorithm
}

nonisolated enum LocalCanvasTool: String, CaseIterable, Sendable {
    case move, pen, brush, scaleA, scaleB, alignmentPoint
}

nonisolated enum LocalFloorPlanEditorMode: String, CaseIterable, Sendable {
    case pen, brush
}

nonisolated enum LocalScaleMarker: Sendable {
    case a, b
}

nonisolated enum FloorPlanRegistrationStep: Int, Sendable {
    case information, alignment, scanning, editing
}

nonisolated enum LocalFloorPlanError: LocalizedError, Sendable {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
