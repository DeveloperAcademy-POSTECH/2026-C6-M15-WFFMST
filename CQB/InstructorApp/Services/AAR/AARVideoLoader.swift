import CQBCore
import Foundation

/// 기록 하나의 영상을 받은 결과
nonisolated enum AARVideoLoadResult: Equatable, Sendable {
    /// 받았다. 재생 순서대로 정렬한 조각 파일
    case loaded([URL])
    /// 영상이 없거나 조각이 아직 다 올라오지 않았다. 다시 요청하면 새로 받는다
    case notUploaded
    /// 네트워크 등으로 받지 못했다. 다시 요청하면 새로 받는다
    case unavailable
}

/// AAR에서 대원 영상 조각을 받아 기기 캐시에 둔다.
/// 요금이 대부분 내려받기에서 나오므로 선택한 대원만 요청하고, 한 번 받은 기록은 다시 받지 않는다.
actor AARVideoLoader {
    private static let completeMarker = "complete.json"

    private let repository: any VideoChunkRepository
    private let cacheRoot: URL
    private var inFlight: [UUID: Task<AARVideoLoadResult, Never>] = [:]

    init(repository: any VideoChunkRepository, cacheRoot: URL = AARVideoLoader.defaultCacheRoot) {
        self.repository = repository
        self.cacheRoot = cacheRoot
    }

    static var defaultCacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AARVideos", isDirectory: true)
    }

    /// - Parameter chunkCount: `Recording.videoChunkCount`. 없거나 0이면 영상이 없다
    func load(_ identity: TrackIdentity, chunkCount: Int?) async -> AARVideoLoadResult {
        guard let chunkCount, chunkCount > 0 else { return .notUploaded }
        let key = identity.recordingID
        let directory = directory(for: identity)
        if let cached = Self.cachedFiles(in: directory, chunkCount: chunkCount) { return .loaded(cached) }
        if let task = inFlight[key] { return await task.value }

        let repository = repository
        let task = Task {
            await Self.download(identity, chunkCount: chunkCount, to: directory, from: repository)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    /// AAR을 마치면 Storage의 영상 조각과 기기 캐시를 지운다.
    /// 삭제가 실패해도 AAR 종료를 막지 않는다. 실패한 기록을 돌려준다.
    /// Storage 영상 1일 자동 삭제 규칙은 아직 설정 전이라, 실패한 영상은 Storage에 남는다.
    func finish(_ recordings: [(identity: TrackIdentity, chunkCount: Int?)]) async -> [TrackIdentity] {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        var failed: [TrackIdentity] = []
        for recording in recordings {
            if let chunkCount = recording.chunkCount, chunkCount > 0 {
                do {
                    try await repository.deleteVideo(recording.identity, chunkCount: chunkCount)
                } catch {
                    failed.append(recording.identity)
                }
            }
            try? FileManager.default.removeItem(at: directory(for: recording.identity))
        }
        return failed
    }

    private func directory(for identity: TrackIdentity) -> URL {
        cacheRoot.appendingPathComponent(identity.recordingID.uuidString, isDirectory: true)
    }

    /// 끝까지 받은 기록만 캐시로 인정한다. 중간에 실패한 조각 파일은 쓰지 않는다.
    private static func cachedFiles(in directory: URL, chunkCount: Int) -> [URL]? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(completeMarker)),
              let names = try? JSONDecoder().decode([String].self, from: data),
              names.count == chunkCount else { return nil }
        let files = names.map { directory.appendingPathComponent($0) }
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        return files
    }

    private static func download(
        _ identity: TrackIdentity,
        chunkCount: Int,
        to directory: URL,
        from repository: any VideoChunkRepository
    ) async -> AARVideoLoadResult {
        try? FileManager.default.removeItem(at: directory)
        do {
            let files = try await repository.downloadVideo(identity, chunkCount: chunkCount, to: directory)
            let names = files.map(\.lastPathComponent)
            try JSONEncoder().encode(names).write(to: directory.appendingPathComponent(completeMarker))
            return .loaded(files)
        } catch RepositoryError.notFound {
            try? FileManager.default.removeItem(at: directory)
            return .notUploaded
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return .unavailable
        }
    }
}
