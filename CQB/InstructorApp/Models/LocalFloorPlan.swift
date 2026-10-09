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

nonisolated struct LocalExtractionResult: Sendable {
    var image: LocalImportedImage
    var baseGrid: LocalObstacleGrid
}

nonisolated struct LocalRegisteredFloorPlan: Equatable, Sendable {
    let id: UUID
    let name: String
    let image: LocalImportedImage
    let baseGrid: LocalObstacleGrid
    let strokes: [LocalEditStroke]
    let outline: [LocalPlanPoint]
    let scale: LocalPlanScale
    let resolvedGrid: LocalObstacleGrid
}

nonisolated enum LocalCanvasTool: String, CaseIterable, Sendable {
    case move, block, open, outline, scaleA, scaleB
}

nonisolated enum FloorPlanRegistrationStep: Int, Sendable {
    case information, editing, scaling, reviewing
}

nonisolated enum LocalFloorPlanError: LocalizedError, Sendable {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
