//
//  StorageVideoChunkRepository.swift
//  CQB
//

import CQBCore
import FirebaseStorage
import Foundation

/// `sessions/{sessionID}/recordings/{recordingID}/video/chunk_NNNN.mp4`를 다룬다.
/// 영상은 메모리에 올리지 않고 파일 그대로 올리고 받는다. 받을 때는 기록 전체 조각을 한 번에 받는다.
public struct StorageVideoChunkRepository: VideoChunkRepository {
    public init() {}

    public func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(size) <= StorageTransfer.maxFileBytes else { throw RepositoryError.fileTooLarge }
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        let reference = try await StorageTransfer.reference(StoragePaths.videoChunk(identity, index: index))
        _ = try await reference.putFileAsync(from: fileURL, metadata: metadata)
    }

    public func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [URL] = []
        for index in 0..<max(chunkCount, 0) {
            let destination = directory.appendingPathComponent(StoragePaths.videoChunkFileName(index: index))
            let reference = try await StorageTransfer.reference(StoragePaths.videoChunk(identity, index: index))
            do {
                _ = try await reference.writeAsync(toFile: destination)
            } catch {
                throw StorageTransfer.mapNotFound(error)
            }
            files.append(destination)
        }
        return files
    }
}
