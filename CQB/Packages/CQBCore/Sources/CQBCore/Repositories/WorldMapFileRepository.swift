import Foundation

/// 스캔 파일 2개(`world-map.arexperience`, `setup.json`) 올리기·받기.
public protocol WorldMapFileRepository: Sendable {
    /// 교관 앱: 훈련장 스캔 결과를 올린다.
    /// `setup.json`이 `reference.setupSHA256`과, 스캔 파일이 `WorldMapSetup.worldMapSHA256`과 맞지 않으면 `RepositoryError.integrityMismatch`.
    func upload(_ files: WorldMapFiles, for reference: WorldMapReference) async throws

    /// 대원 앱: 세션의 스캔을 받는다.
    /// 받은 파일이 `reference.setupSHA256` 또는 `WorldMapSetup.worldMapSHA256`과 맞지 않으면 `RepositoryError.integrityMismatch`.
    func download(_ reference: WorldMapReference) async throws -> WorldMapFiles
}
