import CQBCore
import Foundation

nonisolated enum LocalWorldMapPointTarget: Equatable, Sendable {
    case start, direction, correspondence
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

nonisolated struct LocalWorldMapFrameState: Equatable, Sendable {
    var mapping: LocalWorldMapMappingState
    var trackingMessage: String
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
