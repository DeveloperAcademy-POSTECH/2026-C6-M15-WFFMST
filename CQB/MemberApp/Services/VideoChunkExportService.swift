@preconcurrency import AVFoundation
import Foundation

/// Converts the locally captured MOV into Storage-contract MP4 chunks.
nonisolated struct VideoChunkExportService: Sendable {
    static let targetChunkDuration: TimeInterval = 60
    static let maximumChunkBytes = 20 * 1024 * 1024

    func exportChunks(from sourceURL: URL, to directory: URL) async throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: sourceURL)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0 else { throw ChunkExportError.invalidDuration }

        var urls: [URL] = []
        var start = 0.0
        while start < duration {
            var length = min(Self.targetChunkDuration, duration - start)
            let index = urls.count
            let destination = directory.appendingPathComponent(String(format: "chunk_%04d.mp4", index))
            while true {
                try? FileManager.default.removeItem(at: destination)
                try await export(asset, start: start, duration: length, to: destination)

                let bytes = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                if bytes > 0 && bytes <= Self.maximumChunkBytes {
                    urls.append(destination)
                    start += length
                    break
                }
                try? FileManager.default.removeItem(at: destination)
                guard length > Self.minimumChunkDuration else {
                    throw ChunkExportError.chunkTooLarge(index: index, bytes: bytes)
                }
                length = max(length / 2, Self.minimumChunkDuration)
            }
        }
        return urls
    }

    private func export(_ asset: AVAsset, start: TimeInterval, duration: TimeInterval,
                        to destination: URL) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ChunkExportError.exporterUnavailable
        }
        guard exporter.supportedFileTypes.contains(.mp4) else { throw ChunkExportError.mp4Unsupported }
        exporter.outputURL = destination
        exporter.outputFileType = .mp4
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )

        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .failed:
                    continuation.resume(throwing: exporter.error ?? ChunkExportError.exportFailed)
                default:
                    continuation.resume(throwing: ChunkExportError.exportFailed)
                }
            }
        }
    }

    enum ChunkExportError: LocalizedError {
        case invalidDuration
        case exporterUnavailable
        case mp4Unsupported
        case exportFailed
        case chunkTooLarge(index: Int, bytes: Int)

        var errorDescription: String? {
            switch self {
            case .invalidDuration:
                return "녹화 영상의 길이를 확인할 수 없습니다."
            case .exporterUnavailable:
                return "영상 조각 변환기를 준비할 수 없습니다."
            case .mp4Unsupported:
                return "이 기기에서 MP4 영상 조각을 만들 수 없습니다."
            case .exportFailed:
                return "영상 조각을 만드는 중 오류가 발생했습니다."
            case .chunkTooLarge(let index, let bytes):
                return "영상 조각 \(index + 1)의 크기(\(bytes) bytes)가 Storage 제한을 넘었습니다."
            }
        }
    }

    private static let minimumChunkDuration: TimeInterval = 1
}
