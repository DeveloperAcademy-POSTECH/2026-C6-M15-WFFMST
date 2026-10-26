import Foundation

nonisolated enum ExperimentPhase: Equatable, Sendable {
    case setup
    case preparing
    case ready
    case recording
    case analyzing
    case completed
}

nonisolated enum ManualMarkerKind: String, Codable, CaseIterable, Sendable {
    case sync
    case shotCandidate
    case other

    var title: String {
        switch self {
        case .sync: "동기화"
        case .shotCandidate: "격발 후보"
        case .other: "기타"
        }
    }
}

nonisolated struct ManualMarker: Codable, Identifiable, Sendable {
    let id: UUID
    let kind: ManualMarkerKind
    let recordingTimeSeconds: Double
    let wallClock: Date
}

nonisolated struct SoundClassificationRecord: Codable, Sendable {
    let windowIndex: Int
    let rank: Int
    let windowStartSeconds: Double
    let recordingTimeSeconds: Double
    let durationSeconds: Double
    let identifier: String
    let confidence: Double
}

nonisolated struct AudioCaptureSummary: Codable, Sendable {
    let recordingOriginARTime: Double
    let firstAudioPresentationTime: Double
    let audioStartOffsetSeconds: Double
    let audioDurationSeconds: Double
    let sampleRate: Double
    let channelCount: Int
}

nonisolated struct ExperimentMetadata: Codable, Sendable {
    var schemaVersion = 1
    let sessionID: String
    let participantID: String
    let deviceID: String
    let scenario: String
    let startedAt: Date
    let endedAt: Date
    let operatingSystem: String
    let deviceModel: String
    let classifierIdentifier: String
    let classifierOverlapFactor: Double
    let capture: AudioCaptureSummary
    let classificationWindowCount: Int
    let classificationRowCount: Int
    let manualMarkerCount: Int
}

nonisolated struct LocalExperimentFiles: Sendable {
    let directory: URL
    let audio: URL
    let metadata: URL
    let classifications: URL
    let markers: URL

    var shareURLs: [URL] {
        [metadata, audio, classifications, markers]
    }
}
