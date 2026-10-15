import Foundation

/// 도면 파일 3개(`original.png`, `resolved-mask.bin`, `navigation-map.json`) 올리기·받기.
public protocol FloorPlanFileRepository: Sendable {
    /// 교관 앱: 확정한 도면 파일을 올린다.
    /// `navigation-map.json`이 `reference.navigationSHA256`과 맞지 않으면 `RepositoryError.integrityMismatch`.
    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws

    /// 대원 앱: 세션의 도면 파일을 받는다.
    /// 받은 `navigation-map.json`이 `reference.navigationSHA256`과 맞지 않으면 `RepositoryError.integrityMismatch`.
    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles
}
