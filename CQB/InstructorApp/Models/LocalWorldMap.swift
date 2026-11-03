import CQBCore
import Foundation

nonisolated enum LocalWorldMapPointTarget: Equatable, Sendable {
    case start, direction, checkpoint
}

nonisolated enum LocalScanCheckpointState: Equatable, Sendable {
    case planned, selected, completed
}

nonisolated enum LocalScanCheckpointSelectionResult: Equatable, Sendable {
    case selected
    case startRequired
    case alreadyCaptured
    case invalidCheckpoint
}

nonisolated enum LocalScanCheckpointCaptureResult: Equatable, Sendable {
    case captured
    case startRequired
    case selectionRequired
    case trackingUnavailable(LocalWorldMapTrackingState)
    case alreadyCaptured
    case invalidCheckpoint
    case failed(String)
}

nonisolated enum LocalScanCheckpointAppearance: Equatable, Sendable {
    case labeled, plain
}

nonisolated struct LocalScanCheckpointMarker: Equatable, Sendable {
    let point: LocalPlanPoint
    let number: Int
    let state: LocalScanCheckpointState
}

nonisolated enum LocalWorldMapMappingState: Equatable, Sendable {
    case unavailable, limited, extending, mapped

    var title: String {
        switch self {
        case .unavailable: "준비 중"
        case .limited: "공간 정보 수집 중"
        case .extending: "스캔 범위 확장 중"
        case .mapped: "저장 가능"
        }
    }
}

nonisolated enum LocalWorldMapTrackingState: Equatable, Sendable {
    case normal
    case notAvailable
    case initializing
    case excessiveMotion
    case insufficientFeatures
    case relocalizing
    case limited

    var canCapture: Bool { self == .normal }

    var message: String {
        switch self {
        case .normal: "추적 정상"
        case .notAvailable: "카메라 추적을 시작할 수 없습니다."
        case .initializing: "카메라 위치를 확인하고 있습니다. 주변을 비추며 잠시 천천히 움직여주세요."
        case .excessiveMotion: "기기를 더 천천히 움직여주세요."
        case .insufficientFeatures: "벽 모서리나 주변 사물이 보이도록 비춰주세요."
        case .relocalizing: "저장된 공간을 다시 찾는 중에는 현재 위치를 기록할 수 없습니다."
        case .limited: "카메라 추적이 제한되어 현재 위치를 기록할 수 없습니다."
        }
    }
}

nonisolated enum LocalWorldMapPoseCaptureResult: Equatable, Sendable {
    case captured(ARPose)
    case trackingUnavailable(LocalWorldMapTrackingState)
    case failed(String)
}

nonisolated struct LocalWorldMapFrameState: Equatable, Sendable {
    var mapping: LocalWorldMapMappingState
    var tracking: LocalWorldMapTrackingState
}

nonisolated struct LocalWorldMapScanDraft: Sendable {
    let id: UUID
    let createdAt: Date
    let archive: Data
    let start: WorldMapStart
    let correspondences: [WorldMapCorrespondence]
    let alignment: WorldMapAlignment
    let compression: WorldMapCompression
}
