import AVFoundation
import CQBCore
import Foundation

@main
enum AARVideoChecks {
    static func main() async throws {
        checkTimeline()
        try await checkLoader()
        try await checkComposer()
        print("AARVideoChecks passed")
    }

    // MARK: - 세션 시각 → 영상 위치

    static func checkTimeline() {
        let timeline = AARVideoTimeline(recordingOffset: 3, duration: 20)
        check(timeline.frame(at: 1) == .notStarted, "녹화 시작 전")
        check(timeline.frame(at: 3) == .playing(seconds: 0), "녹화 시작 시각은 영상 0초")
        check(timeline.frame(at: 13.5) == .playing(seconds: 10.5), "기록 시작 오프셋을 뺀다")
        check(timeline.frame(at: 23) == .ended(seconds: 20), "영상이 끝나면 마지막 장면에 멈춘다")
        check(timeline.frame(at: 100) == .ended(seconds: 20), "끝난 뒤에도 마지막 장면")
        check(timeline.endTime == 23, "영상이 끝나는 세션 시각")
    }

    // MARK: - 다운로드·캐시·삭제

    static func checkLoader() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aar-video-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FakeVideoRepository(mode: .success)
        let loader = AARVideoLoader(repository: repository, cacheRoot: root)
        async let first = loader.load(identity, chunkCount: 2)
        async let second = loader.load(identity, chunkCount: 2)
        let results = await [first, second]
        guard case .loaded(let files) = results[0] else { fail("받은 영상") }
        check(results[1] == results[0], "동시 요청은 같은 결과")
        check(files.map(\.lastPathComponent) == ["chunk_0000.mp4", "chunk_0001.mp4"], "재생 순서대로 정렬")
        check(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "캐시 폴더에 파일이 있다")
        check(await loader.load(identity, chunkCount: 2) == results[0], "다시 요청하면 캐시")
        check(await repository.downloads == 1, "같은 기록은 한 번만 받는다 (동시 요청 포함)")

        let fresh = AARVideoLoader(repository: repository, cacheRoot: root)
        check(await fresh.load(identity, chunkCount: 2) == results[0], "앱을 다시 켜도 끝까지 받은 캐시를 쓴다")
        check(await repository.downloads == 1, "캐시가 있으면 내려받지 않는다")

        check(await loader.load(identity, chunkCount: nil) == .notUploaded, "조각 수를 모르면 영상 없음")
        check(await loader.load(identity, chunkCount: 0) == .notUploaded, "조각이 0개면 영상 없음")

        let partialRoot = root.appendingPathComponent("partial")
        let missing = FakeVideoRepository(mode: .missingAfterFirstChunk)
        let missingLoader = AARVideoLoader(repository: missing, cacheRoot: partialRoot)
        check(await missingLoader.load(other, chunkCount: 2) == .notUploaded, "조각이 하나라도 없으면 아직 없음")
        check(!FileManager.default.fileExists(atPath: partialRoot.appendingPathComponent(other.recordingID.uuidString).path),
              "중간에 실패하면 받다 만 파일을 지운다")
        _ = await missingLoader.load(other, chunkCount: 2)
        check(await missing.downloads == 2, "아직 없으면 다음 요청에서 다시 받는다")

        let offline = AARVideoLoader(repository: FakeVideoRepository(mode: .offline), cacheRoot: root)
        check(await offline.load(other, chunkCount: 1) == .unavailable, "네트워크 오류")

        let failedDeletes = await loader.finish([(identity, 2), (other, nil)])
        check(failedDeletes.isEmpty, "삭제 성공")
        check(await repository.deletedRecordings == [identity.recordingID], "영상이 있는 기록만 Storage에서 지운다")
        check(!FileManager.default.fileExists(atPath: files[0].path), "AAR을 마치면 캐시도 지운다")

        let undeletable = AARVideoLoader(repository: FakeVideoRepository(mode: .deleteFails), cacheRoot: root)
        check(await undeletable.finish([(identity, 1)]) == [identity], "삭제 실패한 기록을 알려 주고 멈추지 않는다")
    }

    // MARK: - 조각 이어 붙이기

    static func checkComposer() async throws {
        guard let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: FileManager.default.isExecutableFile) else {
            print("⚠️ ffmpeg가 없어 조각 이어 붙이기 검사를 건너뜁니다")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aar-video-compose-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let chunks = try [2.0, 3.0].enumerated().map { index, seconds in
            let url = directory.appendingPathComponent("chunk_\(index).mp4")
            try run(ffmpeg, [
                "-loglevel", "error",
                "-f", "lavfi", "-i", "color=c=gray:s=160x90:r=10:d=\(seconds)",
                "-f", "lavfi", "-i", "sine=frequency=\(440 + index * 20):sample_rate=48000:duration=\(seconds)",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-profile:a", "aac_low", "-ac", "1", "-b:a", "64k",
                "-shortest", url.path
            ])
            return url
        }
        let composition = try await AARVideoComposer.compose(chunks)
        let duration = try await composition.load(.duration).seconds
        check(abs(duration - 5) < 0.2, "조각 길이를 합친 영상이 된다 (\(duration)초)")
        check(try await composition.loadTracks(withMediaType: .video).count == 1, "영상 트랙 하나로 이어진다")
        check(try await composition.loadTracks(withMediaType: .audio).count == 1, "오디오 트랙 하나로 이어진다")

        let empty = try await AARVideoComposer.compose([])
        check(try await empty.load(.duration) == .zero, "조각이 없으면 빈 영상")
    }

    // MARK: - 도우미

    static let identity = TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID())
    static let other = TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID())

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { fail("\(executable) 실행 실패") }
    }

    static func check(_ condition: Bool, _ message: String) {
        if !condition { fail(message) }
    }

    static func fail(_ message: String) -> Never {
        print("❌ \(message)")
        exit(1)
    }
}

private actor FakeVideoRepository: VideoChunkRepository {
    enum Mode { case success, missingAfterFirstChunk, offline, deleteFails }

    let mode: Mode
    private(set) var downloads = 0
    private(set) var deletedRecordings: [UUID] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {}

    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] {
        downloads += 1
        try await Task.sleep(for: .milliseconds(10))
        if mode == .offline { throw URLError(.notConnectedToInternet) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [URL] = []
        for index in 0..<chunkCount {
            if mode == .missingAfterFirstChunk, index > 0 { throw RepositoryError.notFound }
            let file = directory.appendingPathComponent(String(format: "chunk_%04d.mp4", index))
            try Data([UInt8(index)]).write(to: file)
            files.append(file)
        }
        return files
    }

    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {
        if mode == .deleteFails { throw URLError(.notConnectedToInternet) }
        deletedRecordings.append(identity.recordingID)
    }
}
