import Foundation

/// 화면 이동과 별개로 유지하는 위치 설정 상태. 서버 데이터 계약에는 포함하지 않는다.
nonisolated enum MemberPositioningState: Equatable, Sendable {
    case manualRequired
    case relocalizing
    case manualAvailable
    case automaticReady
    case manualReady
}
