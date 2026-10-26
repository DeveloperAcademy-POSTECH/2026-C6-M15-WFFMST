import Foundation

nonisolated struct ExperimentFileStore: Sendable {
    enum FileStoreError: LocalizedError {
        case invalidIdentifier

        var errorDescription: String? {
            switch self {
            case .invalidIdentifier: "세션·기기 식별자에 사용할 수 있는 문자가 없습니다."
            }
        }
    }

    func makeFiles(sessionID: String, deviceID: String) throws -> LocalExperimentFiles {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = applicationSupport.appendingPathComponent("AudioFusionLab", isDirectory: true)
        let session = try safeComponent(sessionID)
        let device = try safeComponent(deviceID)
        let recordingID = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let directory = root
            .appendingPathComponent(session, isDirectory: true)
            .appendingPathComponent("\(device)-\(recordingID)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        return LocalExperimentFiles(
            directory: directory,
            audio: directory.appendingPathComponent("audio.caf"),
            metadata: directory.appendingPathComponent("metadata.json"),
            classifications: directory.appendingPathComponent("classifications.csv"),
            markers: directory.appendingPathComponent("manual-markers.csv")
        )
    }

    func write(
        metadata: ExperimentMetadata,
        classifications: [SoundClassificationRecord],
        markers: [ManualMarker],
        to files: LocalExperimentFiles
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(metadata).write(to: files.metadata, options: .atomic)
        try classificationCSV(classifications).write(to: files.classifications, atomically: true, encoding: .utf8)
        try markerCSV(markers).write(to: files.markers, atomically: true, encoding: .utf8)
    }

    private func classificationCSV(_ records: [SoundClassificationRecord]) -> String {
        var rows = ["window_index,rank,window_start_seconds,recording_time_seconds,duration_seconds,identifier,confidence"]
        rows.reserveCapacity(records.count + 1)
        for record in records {
            rows.append([
                String(record.windowIndex),
                String(record.rank),
                decimal(record.windowStartSeconds),
                decimal(record.recordingTimeSeconds),
                decimal(record.durationSeconds),
                csv(record.identifier),
                decimal(record.confidence)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func markerCSV(_ markers: [ManualMarker]) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = ["id,kind,recording_time_seconds,wall_clock"]
        rows.reserveCapacity(markers.count + 1)
        for marker in markers {
            rows.append([
                marker.id.uuidString,
                marker.kind.rawValue,
                decimal(marker.recordingTimeSeconds),
                formatter.string(from: marker.wallClock)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func safeComponent(_ raw: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let value = raw.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let sanitized = String(value).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !sanitized.isEmpty else { throw FileStoreError.invalidIdentifier }
        return sanitized
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func csv(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
