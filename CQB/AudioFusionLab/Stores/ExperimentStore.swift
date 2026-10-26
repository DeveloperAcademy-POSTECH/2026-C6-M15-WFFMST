import Foundation
import Observation
import UIKit

@MainActor @Observable
final class ExperimentStore {
    var phase: ExperimentPhase = .setup
    var sessionID = UUID().uuidString
    var participantID = ""
    var deviceID = UIDevice.current.name
    var scenario = ""
    private(set) var markers: [ManualMarker] = []
    private(set) var classifications: [SoundClassificationRecord] = []
    private(set) var classificationWindowCount = 0
    private(set) var completedFiles: LocalExperimentFiles?
    private(set) var errorMessage: String?

    let capture = ARAudioCaptureService()
    let classifierOverlapFactor = 0.5

    private let fileStore = ExperimentFileStore()
    private let classifier = SoundFileClassificationService()
    private var activeFiles: LocalExperimentFiles?
    private var recordingStartedAt: Date?
    private var readinessTask: Task<Void, Never>?

    var canPrepare: Bool {
        !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !participantID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var elapsedSeconds: TimeInterval {
        capture.currentRecordingTime() ?? 0
    }

    var gunshotCandidateWindowCount: Int {
        Set(classifications.lazy.filter { record in
            let identifier = record.identifier.lowercased()
            return record.confidence >= 0.1
                && (identifier.contains("gunshot") || identifier.contains("gunfire"))
        }.map(\.windowIndex)).count
    }

    var topClassifications: [SoundClassificationRecord] {
        classifications.filter { $0.rank == 1 }.suffix(10).reversed()
    }

    func prepare() async {
        guard canPrepare, phase == .setup else { return }
        phase = .preparing
        errorMessage = nil
        do {
            try await capture.prepare()
            readinessTask?.cancel()
            readinessTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled, self.phase == .preparing, !self.capture.isReady {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if !Task.isCancelled, self.phase == .preparing, self.capture.isReady {
                    self.phase = .ready
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .setup
        }
    }

    func startRecording() {
        guard phase == .ready else { return }
        do {
            let files = try fileStore.makeFiles(sessionID: sessionID, deviceID: deviceID)
            try capture.startRecording(to: files.audio)
            activeFiles = files
            recordingStartedAt = .now
            markers = []
            classifications = []
            classificationWindowCount = 0
            completedFiles = nil
            errorMessage = nil
            phase = .recording
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addMarker(_ kind: ManualMarkerKind) {
        guard phase == .recording, let time = capture.currentRecordingTime() else { return }
        markers.append(ManualMarker(id: UUID(), kind: kind, recordingTimeSeconds: time, wallClock: .now))
    }

    func stopRecording() async {
        guard phase == .recording,
              let files = activeFiles,
              let startedAt = recordingStartedAt else { return }
        phase = .analyzing
        errorMessage = nil
        do {
            let captureSummary = try await capture.stopRecording()
            capture.stopSession()
            let analysis = try await classifier.analyze(
                audioURL: files.audio,
                audioStartOffsetSeconds: captureSummary.audioStartOffsetSeconds,
                overlapFactor: classifierOverlapFactor
            )
            let endedAt = Date.now
            let metadata = ExperimentMetadata(
                sessionID: sessionID,
                participantID: participantID,
                deviceID: deviceID,
                scenario: scenario,
                startedAt: startedAt,
                endedAt: endedAt,
                operatingSystem: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                deviceModel: UIDevice.current.model,
                classifierIdentifier: "SNClassifierIdentifier.version1",
                classifierOverlapFactor: classifierOverlapFactor,
                capture: captureSummary,
                classificationWindowCount: analysis.windowCount,
                classificationRowCount: analysis.records.count,
                manualMarkerCount: markers.count
            )
            try fileStore.write(
                metadata: metadata,
                classifications: analysis.records,
                markers: markers,
                to: files
            )
            classifications = analysis.records
            classificationWindowCount = analysis.windowCount
            completedFiles = files
            phase = .completed
        } catch {
            capture.stopSession()
            errorMessage = error.localizedDescription
            phase = .setup
        }
    }

    func reset() {
        readinessTask?.cancel()
        readinessTask = nil
        capture.stopSession()
        markers = []
        classifications = []
        classificationWindowCount = 0
        activeFiles = nil
        completedFiles = nil
        recordingStartedAt = nil
        errorMessage = nil
        phase = .setup
    }
}
