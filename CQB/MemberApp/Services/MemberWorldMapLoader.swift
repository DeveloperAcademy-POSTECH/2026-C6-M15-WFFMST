import ARKit
import Compression
import CQBCore
import CryptoKit
import Foundation

nonisolated struct LoadedMemberWorldMap {
    let worldMap: ARWorldMap
    let setup: WorldMapSetup
}

nonisolated enum MemberWorldMapLoader {
    static let maximumArchiveBytes = 50 * 1_048_576
    static let maximumSetupBytes = 1_048_576
    static let maximumDecompressedBytes = 128 * 1_048_576

    @concurrent static func load(files: WorldMapFiles, reference: WorldMapReference) async throws -> sending LoadedMemberWorldMap {
        let (data, setup) = try decodeArchive(files: files, reference: reference)
        try Task.checkCancellation()
        let worldMap: ARWorldMap
        do {
            guard let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                throw MemberWorldMapLoadError.invalidArchive
            }
            worldMap = decoded
        } catch {
            throw MemberWorldMapLoadError.invalidArchive
        }
        try Task.checkCancellation()
        return LoadedMemberWorldMap(worldMap: worldMap, setup: setup)
    }

    /// 저장된 바이트의 검증과 압축 해제를 ARKit 복원 전에 완료한다.
    static func decodeArchive(files: WorldMapFiles, reference: WorldMapReference) throws -> (Data, WorldMapSetup) {
        try Task.checkCancellation()
        guard files.worldMapArchive.count <= maximumArchiveBytes,
              files.setupJSON.count <= maximumSetupBytes else {
            throw RepositoryError.fileTooLarge
        }
        guard sha256(files.setupJSON) == reference.setupSHA256.lowercased(),
              let setup = try? JSONDecoder().decode(WorldMapSetup.self, from: files.setupJSON),
              setup.schemaVersion == 1, setup.matches(reference),
              !files.worldMapArchive.isEmpty,
              setup.worldMapBytes == files.worldMapArchive.count,
              sha256(files.worldMapArchive) == setup.worldMapSHA256.lowercased(),
              setup.alignment.rotationDegrees.isFinite,
              setup.alignment.pixelsPerMeter.isFinite, setup.alignment.pixelsPerMeter > 0,
              setup.alignment.translation.x.isFinite, setup.alignment.translation.y.isFinite else {
            throw RepositoryError.integrityMismatch
        }
        let data: Data
        switch setup.compression {
        case .none: data = files.worldMapArchive
        case .lzfse: data = try decompress(files.worldMapArchive)
        }
        try Task.checkCancellation()
        return (data, setup)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func decompress(_ data: Data, maximumOutputBytes: Int = maximumDecompressedBytes) throws -> Data {
        try Task.checkCancellation()
        guard maximumOutputBytes > 0, maximumOutputBytes <= maximumDecompressedBytes else {
            throw RepositoryError.integrityMismatch
        }
        guard !data.isEmpty else { throw MemberWorldMapLoadError.invalidCompressedArchive }
        // 입력 전체를 반복해서 해제하지 않고, 고정 버퍼로 읽으며 출력 상한과 취소를 검사한다.
        return try data.withUnsafeBytes { source in
            var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
            return try buffer.withUnsafeMutableBufferPointer { destination in
                var stream = compression_stream(
                    dst_ptr: destination.baseAddress!, dst_size: destination.count,
                    src_ptr: source.bindMemory(to: UInt8.self).baseAddress!, src_size: data.count,
                    state: nil
                )
                guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZFSE)
                    == COMPRESSION_STATUS_OK else { throw MemberWorldMapLoadError.invalidCompressedArchive }
                defer { compression_stream_destroy(&stream) }
                stream.src_ptr = source.bindMemory(to: UInt8.self).baseAddress!
                stream.src_size = data.count
                var output = Data()
                while true {
                    try Task.checkCancellation()
                    // 상한 + 1 바이트를 읽어 정확히 상한인 출력과 초과 출력을 구분한다.
                    let capacity = min(destination.count, maximumOutputBytes - output.count + 1)
                    stream.dst_ptr = destination.baseAddress!
                    stream.dst_size = capacity
                    let remainingInput = stream.src_size
                    let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    guard status != COMPRESSION_STATUS_ERROR else {
                        throw MemberWorldMapLoadError.invalidCompressedArchive
                    }
                    let count = capacity - stream.dst_size
                    guard count <= maximumOutputBytes - output.count else {
                        throw MemberWorldMapLoadError.decompressedSizeLimitExceeded
                    }
                    output.append(destination.baseAddress!, count: count)
                    if status == COMPRESSION_STATUS_END {
                        guard !output.isEmpty else {
                            throw MemberWorldMapLoadError.invalidCompressedArchive
                        }
                        return output
                    }
                    guard status == COMPRESSION_STATUS_OK,
                          count > 0 || stream.src_size < remainingInput else {
                        throw MemberWorldMapLoadError.invalidCompressedArchive
                    }
                }
            }
        }
    }
}

nonisolated enum MemberWorldMapLoadError: LocalizedError, Equatable {
    case invalidCompressedArchive
    case decompressedSizeLimitExceeded
    case invalidArchive

    var errorDescription: String? {
        switch self {
        case .invalidCompressedArchive:
            "공간 스캔 파일이 손상되어 압축을 해제할 수 없습니다. 교관에게 공간 스캔을 다시 저장해 달라고 요청해주세요."
        case .decompressedSizeLimitExceeded:
            "공간 스캔 원본이 복원 한도(128MiB)를 초과했습니다. 교관에게 공간 스캔을 다시 저장해 달라고 요청해주세요."
        case .invalidArchive:
            "공간 스캔 파일을 복원할 수 없습니다. 교관에게 공간 스캔을 다시 저장해 달라고 요청해주세요."
        }
    }
}
