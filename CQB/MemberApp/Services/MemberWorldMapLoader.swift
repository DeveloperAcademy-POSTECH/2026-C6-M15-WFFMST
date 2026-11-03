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
    static let maximumDecompressedBytes = 128 * 1_048_576

    @concurrent static func load(files: WorldMapFiles, reference: WorldMapReference) async throws -> sending LoadedMemberWorldMap {
        let setup = try JSONDecoder().decode(WorldMapSetup.self, from: files.setupJSON)
        guard setup.schemaVersion == 1, setup.matches(reference),
              sha256(files.setupJSON) == reference.setupSHA256.lowercased(),
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
        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            throw RepositoryError.integrityMismatch
        }
        return LoadedMemberWorldMap(worldMap: worldMap, setup: setup)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func decompress(_ data: Data, maximumOutputBytes: Int = maximumDecompressedBytes) throws -> Data {
        // 압축 파일로 인한 무제한 메모리 할당을 방지한다. 저장 파일 제한은 Repository에서 검사한다.
        guard maximumOutputBytes > 0, maximumOutputBytes <= maximumDecompressedBytes else {
            throw RepositoryError.integrityMismatch
        }
        var capacity = min(1_048_576, maximumOutputBytes)
        while true {
            // 상한 + 1 바이트까지 받아야 정확히 상한인 출력과 초과 출력을 구분할 수 있다.
            let destinationCapacity = capacity == maximumOutputBytes ? maximumOutputBytes + 1 : capacity
            var output = Data(count: destinationCapacity)
            let count = output.withUnsafeMutableBytes { destination in
                data.withUnsafeBytes { source in
                    guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                          let src = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(dst, destinationCapacity, src, data.count, nil, COMPRESSION_LZFSE)
                }
            }
            if count > 0, count < destinationCapacity { return output.prefix(count) }
            guard count == destinationCapacity, capacity < maximumOutputBytes else {
                throw RepositoryError.integrityMismatch
            }
            capacity = min(capacity * 2, maximumOutputBytes)
        }
    }
}
