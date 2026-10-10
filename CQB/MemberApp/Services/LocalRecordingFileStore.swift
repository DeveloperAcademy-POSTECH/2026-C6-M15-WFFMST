import Foundation
import CryptoKit

nonisolated struct LocalRecordingFileStore: Sendable {
    func makeFiles(recordingID: UUID) throws -> LocalRecordingFiles {
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = root.appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(recordingID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return LocalRecordingFiles(directory: directory)
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

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
