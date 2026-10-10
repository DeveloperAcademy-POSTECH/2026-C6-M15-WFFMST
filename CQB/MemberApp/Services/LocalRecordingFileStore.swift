import Foundation

/// Creates app-private video URLs. Upload and deletion policies are intentionally separate.
struct LocalRecordingFileStore {
    func makeRecordingURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let recordingsDirectory = applicationSupport.appending(
            path: "Recordings",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return recordingsDirectory
            .appending(path: "training-\(timestamp)-\(UUID().uuidString).mov")
    }
}
