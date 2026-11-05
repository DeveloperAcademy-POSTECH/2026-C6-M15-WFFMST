@preconcurrency import AVFoundation
import CQBCore
import Foundation
import os
@preconcurrency import SoundAnalysis

/// 녹화 중 마이크의 압축 전 소리(PCM)로 큰 소리 후보를 모은다(#172).
/// 영상 작성과 분리된 자기 직렬 큐에서만 상태를 바꾸므로 분석이 늦어도 녹화를 막지 않는다.
/// 후보는 거르지 않고 근거 값과 함께 남긴다. 최종 판정은 교관 앱이 한다.
nonisolated final class MemberSoundCandidateRecorder: @unchecked Sendable {
    struct Result: Sendable, Equatable {
        let analyzedRanges: [SoundTimeRange]
        let candidates: [SoundCandidate]
    }

    static let detector = SoundDetectorIdentity(name: "gunshot-combined", version: "713e743", settingsID: "onset-standard")
    /// 다음 버퍼가 이보다 늦게 오면 녹음이 끊긴 것으로 보고 새 구간을 연다.
    static let gapTolerance = 0.1

    private let queue = DispatchQueue(label: "com.cqb.member.sound-candidates", qos: .utility)
    private let config = FusionConfig.standard
    private var recordingStart: Double?
    private var segment: Segment?
    private var ranges: [SoundTimeRange] = []
    private var candidates: [SoundCandidate] = []
    private var failed = false

    /// 첫 녹화 프레임 시각(호스트 시계)이 정해진 뒤 부른다. 그 전에 온 버퍼는 분석하지 않는다.
    func begin(recordingStart: Double) {
        queue.async { [self] in
            reset()
            self.recordingStart = recordingStart
        }
    }

    /// 호스트 시계로 바꾼 마이크 버퍼. `ARFrameVideoWriter.append(audioSampleBuffer:)`와 같은 입력이다.
    func append(_ sampleBuffer: CMSampleBuffer) {
        nonisolated(unsafe) let captured = sampleBuffer
        queue.async { [self] in
            guard let recordingStart, !failed else { return }
            let start = CMSampleBufferGetPresentationTimeStamp(captured).seconds
            let end = RecordingAudioSamples.endTime(of: captured)
            guard start.isFinite, end > recordingStart else { return }
            guard let buffer = Self.floatMonoBuffer(from: captured) else { return }
            do {
                if let current = segment,
                   current.sampleRate != buffer.format.sampleRate || start - current.hostEnd > Self.gapTolerance {
                    closeSegment()
                }
                if segment == nil { segment = try Segment(hostStart: start, format: buffer.format, config: config) }
                segment?.append(buffer, hostEnd: end)
            } catch {
                failed = true
                segment = nil
            }
        }
    }

    /// 전화 등으로 녹음이 끊겼다. 지금 구간을 닫고 다음 버퍼에서 새 구간을 연다.
    func interrupt() {
        queue.async { [self] in closeSegment() }
    }

    /// 녹화를 마쳤다. 분석을 시작하지 못했으면 빈 결과, 분석 중 실패했으면 nil이다.
    func finish() async -> Result? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                closeSegment()
                let result = failed ? nil : Result(analyzedRanges: ranges, candidates: candidates.sorted { $0.time < $1.time })
                reset()
                continuation.resume(returning: result)
            }
        }
    }

    func cancel() {
        queue.async { [self] in reset() }
    }

    private func reset() {
        recordingStart = nil
        segment = nil
        ranges = []
        candidates = []
        failed = false
    }

    private func closeSegment() {
        guard let current = segment, let recordingStart else { segment = nil; return }
        segment = nil
        let closed = current.close()
        guard let output = Self.segmentOutput(
            hostStart: current.hostStart, hostEnd: current.hostEnd, recordingStart: recordingStart,
            closed: closed, config: config
        ) else { return }
        ranges = Self.appending(output.range, to: ranges)
        candidates += output.candidates
    }

    /// 닫은 구간 하나를 분석 구간과 후보로 바꾼다. 남길 것이 없으면 nil이다.
    /// 분류기가 오류로 멈춘 구간은 점수가 0인 가짜 결과가 되므로 분석 구간과 후보에서 통째로 뺀다(#196).
    /// 읽는 쪽은 그 시간을 "소리 없음"이 아니라 "분석 안 됨"으로 본다.
    static func segmentOutput(
        hostStart: Double,
        hostEnd: Double,
        recordingStart: Double,
        closed: ClosedSegment,
        config: FusionConfig
    ) -> (range: SoundTimeRange, candidates: [SoundCandidate])? {
        guard !closed.classifierFailed else { return nil }
        let rangeStart = max(0, hostStart - recordingStart)
        let rangeEnd = hostEnd - recordingStart
        guard rangeEnd > rangeStart else { return nil }
        var result: [SoundCandidate] = []
        for onset in closed.onsets {
            let time = hostStart + onset.audioSeconds - recordingStart
            guard time >= rangeStart, time <= rangeEnd else { continue }
            let probe = onset.audioSeconds + config.probeDelaySeconds
            result.append(SoundCandidate(
                time: time,
                peakLevelDBFS: onset.levelDB,
                decaySeconds: onset.decaySeconds,
                classifierScores: scores(at: probe, windows: closed.windows, labels: config.labels)
            ))
        }
        return (SoundTimeRange(start: rangeStart, end: rangeEnd), result)
    }

    /// 구간을 끝에 붙인다. 앞 구간과 끝이 맞닿거나 겹치면 하나로 합친다.
    /// 포맷이 바뀌거나 끊김 알림만 오고 버퍼는 이어질 때 새 구간이 앞 구간 끝에서 시작한다.
    /// 구간은 양 끝을 포함하므로 그대로 두면 같은 시각이 두 구간에 속해 계약 검증에 걸린다(#178).
    static func appending(_ range: SoundTimeRange, to ranges: [SoundTimeRange]) -> [SoundTimeRange] {
        guard let last = ranges.last, range.start <= last.end else { return ranges + [range] }
        return ranges.dropLast() + [SoundTimeRange(start: last.start, end: max(last.end, range.end))]
    }

    /// 후보 직후 시점을 담은 분류기 창들에서 라벨별 최고 점수. `FusionJudge`와 같은 시점 규칙이다.
    static func scores(at probe: Double, windows: [LabeledWindow], labels: [String]) -> [String: Double] {
        let covering = windows.filter { $0.start <= probe && $0.end >= probe }
        var result: [String: Double] = [:]
        for label in labels {
            result[label] = covering.compactMap { $0.confidences[label] }.max() ?? 0
        }
        return result
    }

    /// 마이크 버퍼를 감지기와 분류기가 받는 32비트 실수 모노 버퍼로 바꾼다.
    static func floatMonoBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: description)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else { return nil }
        source.frameLength = frameCount
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: source.mutableAudioBufferList) == noErr else { return nil }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sourceFormat.sampleRate, channels: 1, interleaved: false) else { return nil }
        if sourceFormat == targetFormat { return source }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
              let target = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return nil }
        do { try converter.convert(to: target, from: source) } catch { return nil }
        return target.frameLength > 0 ? target : nil
    }
}

/// 분류기 창 하나의 라벨별 신뢰도. 시각은 구간 시작부터의 오디오 초다.
nonisolated struct LabeledWindow: Sendable, Equatable {
    let start: Double
    let end: Double
    let confidences: [String: Double]
}

/// 구간 안의 급상승 하나. 시각은 구간 시작부터의 오디오 초다.
nonisolated struct SegmentOnset: Sendable, Equatable {
    let audioSeconds: Double
    let levelDB: Double
    let decaySeconds: Double?
}

/// 닫은 구간에서 나온 급상승과 분류기 창. 분류기가 오류로 멈췄으면 `classifierFailed`다.
nonisolated struct ClosedSegment: Sendable, Equatable {
    let onsets: [SegmentOnset]
    let windows: [LabeledWindow]
    let classifierFailed: Bool
}

/// 끊기지 않은 녹음 한 구간. 구간마다 감지기와 분류기를 새로 만든다.
nonisolated private final class Segment {
    let hostStart: Double
    let sampleRate: Double
    private(set) var hostEnd: Double
    private var frameCursor: AVAudioFramePosition = 0
    private var onsets: [SegmentOnset] = []
    private let detector: OnsetDetector
    private let analyzer: SNAudioStreamAnalyzer
    private let observer: WindowCollector

    init(hostStart: Double, format: AVAudioFormat, config: FusionConfig) throws {
        self.hostStart = hostStart
        hostEnd = hostStart
        sampleRate = format.sampleRate
        detector = OnsetDetector(sampleRate: format.sampleRate)
        analyzer = SNAudioStreamAnalyzer(format: format)
        observer = WindowCollector(labels: config.labels)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: config.windowSeconds, preferredTimescale: 48_000)
        request.overlapFactor = config.overlapFactor
        try analyzer.add(request, withObserver: observer)
    }

    func append(_ buffer: AVAudioPCMBuffer, hostEnd: Double) {
        onsets += detector.process(buffer, startFrame: frameCursor).map {
            SegmentOnset(audioSeconds: $0.audioSeconds, levelDB: $0.levelDB, decaySeconds: $0.decaySeconds)
        }
        analyzer.analyze(buffer, atAudioFramePosition: frameCursor)
        frameCursor += AVAudioFramePosition(buffer.frameLength)
        self.hostEnd = max(self.hostEnd, hostEnd)
    }

    /// 분류기에 남은 창을 마저 받는다. 잔향을 재는 중이던 구간 끝 0.5초 안의 후보는 잔향 없이(`nil`) 남긴다(#196).
    func close() -> ClosedSegment {
        analyzer.completeAnalysis()
        let unfinished = detector.drainUnfinished().map {
            SegmentOnset(audioSeconds: $0.audioSeconds, levelDB: $0.levelDB, decaySeconds: nil)
        }
        return ClosedSegment(
            onsets: (onsets + unfinished).sorted { $0.audioSeconds < $1.audioSeconds },
            windows: observer.windows,
            classifierFailed: observer.didFail
        )
    }
}

/// 분류기 창을 모은다. 분류기가 오류로 멈추면 `didFail`이 된다.
nonisolated final class WindowCollector: NSObject, SNResultsObserving, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "MemberSoundCandidateRecorder")
    private let labels: [String]
    private let lock = NSLock()
    private var collected: [LabeledWindow] = []
    private var failed = false

    init(labels: [String]) {
        self.labels = labels
    }

    var windows: [LabeledWindow] { lock.withLock { collected } }
    var didFail: Bool { lock.withLock { failed } }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        Self.logger.error("소리 분류 실패: \(error.localizedDescription, privacy: .private)")
        lock.withLock { failed = true }
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        var confidences: [String: Double] = [:]
        for label in labels {
            if let classification = result.classification(forIdentifier: label) {
                confidences[label] = classification.confidence
            }
        }
        let start = result.timeRange.start.seconds
        let window = LabeledWindow(start: start, end: start + result.timeRange.duration.seconds, confidences: confidences)
        lock.withLock { collected.append(window) }
    }
}
