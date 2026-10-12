import CQBCore
import Foundation

nonisolated struct LocalVideoChunk: Sendable {
    let index: Int
    let url: URL
}

nonisolated struct VideoChunkUploadStatus: Sendable {
    let uploadedCount: Int
    let failedCount: Int
    let activeIndex: Int?
    let latestError: String?
}

/// Keeps capture independent from network availability while sending completed chunks in index order.
actor VideoChunkUploadQueue {
    private let repository: any VideoChunkRepository
    private let fileStore: LocalRecordingFileStore
    private let manifestURL: URL
    private let identity: TrackIdentity
    private let onStatus: @Sendable (VideoChunkUploadStatus) -> Void

    private var manifest: RecordingUploadManifest
    private var pending: [Int: URL] = [:]
    private var failed: [Int: URL] = [:]
    private var nextIndex = 0
    private var activeIndex: Int?
    private var latestError: String?
    private var drainTask: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        repository: any VideoChunkRepository,
        fileStore: LocalRecordingFileStore,
        manifestURL: URL,
        identity: TrackIdentity,
        manifest: RecordingUploadManifest,
        onStatus: @escaping @Sendable (VideoChunkUploadStatus) -> Void
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.manifestURL = manifestURL
        self.identity = identity
        self.manifest = manifest
        self.onStatus = onStatus
    }

    func enqueue(_ chunk: LocalVideoChunk) {
        guard chunk.index >= nextIndex,
              !manifest.uploadedVideoChunkIndexes.contains(chunk.index),
              pending[chunk.index] == nil,
              failed[chunk.index] == nil else { return }
        pending[chunk.index] = chunk.url
        startDrainingIfNeeded()
    }

    func setFinalChunkCount(_ count: Int) throws {
        var knownIndexes = Set(manifest.uploadedVideoChunkIndexes)
            .union(failed.keys)
            .union(pending.keys)
        if let activeIndex { knownIndexes.insert(activeIndex) }
        guard count >= 0, (0..<count).allSatisfy(knownIndexes.contains) else {
            let missing = (0..<count).first(where: { !knownIndexes.contains($0) }) ?? 0
            throw UploadQueueError.missingChunk(missing)
        }
        manifest.videoChunkCount = count
        try persistManifest()
    }

    func waitForInitialUploads() async {
        await waitUntilIdle()
    }

    func retryFailedChunks() async throws {
        await waitUntilIdle()
        for index in Array(failed.keys).sorted() {
            guard let url = failed[index] else { continue }
            activeIndex = index
            latestError = nil
            publishStatus()
            do {
                try await repository.upload(fileURL: url, identity: identity, index: index)
                failed[index] = nil
                manifest.uploadedVideoChunkIndexes.insert(index)
                try persistManifest()
            } catch {
                activeIndex = nil
                latestError = error.localizedDescription
                publishStatus()
                throw error
            }
        }
        activeIndex = nil
        latestError = nil
        publishStatus()
    }

    func markTrackResultUploaded() throws {
        manifest.uploadedTrackResult = true
        try persistManifest()
    }

    func currentManifest() -> RecordingUploadManifest {
        manifest
    }

    func failedChunkCount() -> Int { failed.count }

    private func startDrainingIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { await drainInOrder() }
    }

    private func drainInOrder() async {
        while let url = pending.removeValue(forKey: nextIndex) {
            let index = nextIndex
            activeIndex = index
            latestError = nil
            publishStatus()
            do {
                try await repository.upload(fileURL: url, identity: identity, index: index)
                manifest.uploadedVideoChunkIndexes.insert(index)
                try persistManifest()
            } catch {
                failed[index] = url
                latestError = error.localizedDescription
            }
            nextIndex += 1
            activeIndex = nil
            publishStatus()
        }
        drainTask = nil
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if pending[nextIndex] != nil { startDrainingIfNeeded() }
    }

    private func waitUntilIdle() async {
        guard drainTask != nil else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    private func persistManifest() throws {
        try fileStore.saveUploadManifest(manifest, to: manifestURL)
    }

    private func publishStatus() {
        onStatus(VideoChunkUploadStatus(
            uploadedCount: manifest.uploadedVideoChunkIndexes.count,
            failedCount: failed.count,
            activeIndex: activeIndex,
            latestError: latestError
        ))
    }

    private enum UploadQueueError: LocalizedError {
        case missingChunk(Int)

        var errorDescription: String? {
            switch self {
            case .missingChunk(let index): "영상 조각 \(index + 1)을 찾을 수 없습니다."
            }
        }
    }
}
