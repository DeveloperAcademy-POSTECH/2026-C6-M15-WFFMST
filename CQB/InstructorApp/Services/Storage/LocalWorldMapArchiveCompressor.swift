import CQBCore
import Foundation
import OSLog

nonisolated enum LocalWorldMapArchiveCompressor {
    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "WorldMapCompression")
    // #150 MemberWorldMapLoader의 기존 압축 해제 상한과 같다.
    static let maximumRestorableArchiveBytes = 128 * 1_024 * 1_024

    @concurrent static func compress(_ archive: Data) async throws -> Data {
        try Task.checkCancellation()
        guard !archive.isEmpty else { throw LocalWorldMapCompressionError.emptyArchive }
        guard archive.count <= maximumRestorableArchiveBytes else {
            throw LocalWorldMapCompressionError.restorationLimitExceeded(actualBytes: archive.count)
        }
        let started = ContinuousClock.now
        let compressed: Data
        do {
            compressed = try (archive as NSData).compressed(using: .lzfse) as Data
        } catch {
            throw LocalWorldMapCompressionError.compressionFailed
        }
        try Task.checkCancellation()
        let duration = started.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000
            + Double(duration.attoseconds) / 1_000_000_000_000_000
        let ratio = Double(compressed.count) / Double(archive.count)
        logger.info("WorldMap LZFSE: original_bytes=\(archive.count, privacy: .public) compressed_bytes=\(compressed.count, privacy: .public) ratio=\(ratio, privacy: .public) duration_ms=\(milliseconds, privacy: .public)")
        try LocalUploadSizeValidator.validateWorldMapArchive(compressed, compression: .lzfse)
        return compressed
    }
}

nonisolated enum LocalWorldMapCompressionError: LocalizedError {
    case emptyArchive
    case compressionFailed
    case restorationLimitExceeded(actualBytes: Int)

    var errorDescription: String? {
        switch self {
        case .emptyArchive:
            "저장할 공간 스캔 데이터가 없습니다."
        case .compressionFailed:
            "공간 스캔 파일을 압축하지 못했습니다. 다시 시도해주세요."
        case .restorationLimitExceeded(let actualBytes):
            "공간 스캔 원본이 대원 앱의 복원 한도를 초과했습니다.\n"
                + "원본 용량: \(LocalUploadFileSizeError.formattedBytes(actualBytes))\n"
                + "복원 한도: \(LocalUploadFileSizeError.formattedBytes(LocalWorldMapArchiveCompressor.maximumRestorableArchiveBytes))"
        }
    }
}
