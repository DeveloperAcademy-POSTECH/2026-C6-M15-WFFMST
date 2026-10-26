@preconcurrency import SoundAnalysis
import CoreMedia
import Foundation

@MainActor
final class SoundFileClassificationService {
    struct AnalysisOutput: Sendable {
        let records: [SoundClassificationRecord]
        let windowCount: Int
    }

    enum AnalysisError: LocalizedError {
        case cancelled
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "오디오 분류가 파일 끝까지 완료되지 않았습니다."
            case .requestFailed(let reason): "Sound Classifier 실행에 실패했습니다: \(reason)"
            }
        }
    }

    func analyze(
        audioURL: URL,
        audioStartOffsetSeconds: Double,
        overlapFactor: Double
    ) async throws -> AnalysisOutput {
        let analyzer = try SNAudioFileAnalyzer(url: audioURL)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.overlapFactor = overlapFactor
        let observer = ClassificationObserver(audioStartOffsetSeconds: audioStartOffsetSeconds)
        try analyzer.add(request, withObserver: observer)

        let didReachEnd = await withCheckedContinuation { continuation in
            analyzer.analyze { reachedEnd in
                continuation.resume(returning: reachedEnd)
            }
        }
        guard didReachEnd else { throw AnalysisError.cancelled }
        if let failure = observer.failureDescription() {
            throw AnalysisError.requestFailed(failure)
        }
        let snapshot = observer.snapshot()
        return AnalysisOutput(records: snapshot.records, windowCount: snapshot.windowCount)
    }
}

nonisolated private final class ClassificationObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    nonisolated private struct Window: Sendable {
        let start: Double
        let duration: Double
        let classifications: [(identifier: String, confidence: Double)]
    }

    private let lock = NSLock()
    private let audioStartOffsetSeconds: Double
    private var windows: [Window] = []
    private var failure: String?

    init(audioStartOffsetSeconds: Double) {
        self.audioStartOffsetSeconds = audioStartOffsetSeconds
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let start = result.timeRange.start.seconds
        let duration = result.timeRange.duration.seconds
        let classifications = result.classifications.map {
            (identifier: $0.identifier, confidence: $0.confidence)
        }
        lock.lock()
        windows.append(Window(start: start, duration: duration, classifications: classifications))
        lock.unlock()
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {
        lock.lock()
        failure = error.localizedDescription
        lock.unlock()
    }

    func snapshot() -> (records: [SoundClassificationRecord], windowCount: Int) {
        lock.lock()
        let captured = windows
        lock.unlock()

        let ordered = captured.sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.duration < rhs.duration }
            return lhs.start < rhs.start
        }
        var records: [SoundClassificationRecord] = []
        for (windowIndex, window) in ordered.enumerated() {
            for (rank, classification) in window.classifications.enumerated() {
                records.append(SoundClassificationRecord(
                    windowIndex: windowIndex,
                    rank: rank + 1,
                    windowStartSeconds: window.start,
                    recordingTimeSeconds: audioStartOffsetSeconds + window.start,
                    durationSeconds: window.duration,
                    identifier: classification.identifier,
                    confidence: classification.confidence
                ))
            }
        }
        return (records, ordered.count)
    }

    func failureDescription() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }
}
