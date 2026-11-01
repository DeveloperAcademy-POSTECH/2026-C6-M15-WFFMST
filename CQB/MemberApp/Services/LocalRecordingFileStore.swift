import Foundation
import CryptoKit

nonisolated struct LocalRecordingFileStore: Sendable {
    enum Scope: Sendable, Equatable {
        case operational
        case demo(runID: UUID)
    }

    private let scope: Scope
    private let baseDirectory: URL?

    init(scope: Scope = .operational, baseDirectory: URL? = nil) {
        self.scope = scope
        self.baseDirectory = baseDirectory
    }

    func makeFiles(recordingID: UUID) throws -> LocalRecordingFiles {
        var directory = try recordingRoot()
            .appendingPathComponent(recordingID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return LocalRecordingFiles(directory: directory)
    }

    /// Remove only this store's uncommitted startup files, never a saved recording.
    func discardUncommittedFiles(_ files: LocalRecordingFiles) throws {
        let directory = files.directory.standardizedFileURL
        guard directory.deletingLastPathComponent() == (try recordingRoot()).standardizedFileURL,
              UUID(uuidString: directory.lastPathComponent) != nil else {
            throw CleanupError.invalidRecordingDirectory
        }
        guard !FileManager.default.fileExists(atPath: files.raw.path),
              !FileManager.default.fileExists(atPath: files.result.path) else {
            throw CleanupError.savedRecording
        }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// 데모 실행 디렉터리만 제거한다. 운영 Recordings 경로에는 사용할 수 없다.
    func removeDemoRun() throws {
        guard case .demo = scope else { throw CleanupError.operationalScope }
        let directory = try recordingRoot()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// 원본은 최초 저장만 허용한다. 해시는 실제로 저장한 바이트를 대상으로 한다.
    func saveRaw(_ raw: RawTrackDocument, to url: URL) throws -> String {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let data = try encode(raw)
        try data.write(to: url, options: .atomic)
        return Self.sha256(data)
    }

    func save<T: Encodable>(_ value: T, to url: URL) throws {
        try encode(value).write(to: url, options: .atomic)
    }

    func loadUploadManifest(from url: URL) throws -> RecordingUploadManifest? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingUploadManifest.self, from: Data(contentsOf: url))
    }

    func saveUploadManifest(_ manifest: RecordingUploadManifest, to url: URL) throws {
        try save(manifest, to: url)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func recordingRoot() throws -> URL {
        switch scope {
        case .operational:
            let root = try baseDirectory ?? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return root.appendingPathComponent("Recordings", isDirectory: true)
        case .demo(let runID):
            let root = try baseDirectory ?? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return root.appendingPathComponent("DemoRecordings", isDirectory: true)
                .appendingPathComponent(runID.uuidString, isDirectory: true)
        }
    }

    private enum CleanupError: Error {
        case operationalScope
        case invalidRecordingDirectory
        case savedRecording
    }
}
