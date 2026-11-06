@preconcurrency import AVFoundation
import UIKit

nonisolated final class ARFrameVideoWriter: @unchecked Sendable {
    static let targetChunkDuration: TimeInterval = 30
    static let maximumChunkBytes = 20 * 1024 * 1024

    enum RecorderError: LocalizedError {
        case alreadyRecording, cannotAddVideoInput, cannotAddAudioInput, notRecording
        case cannotStartWriter(String), writerFailed(String), chunkTooLarge(index: Int, bytes: Int)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: "이미 영상을 녹화하고 있습니다."
            case .cannotAddVideoInput: "영상 인코더 입력을 만들 수 없습니다."
            case .cannotAddAudioInput: "오디오 인코더 입력을 만들 수 없습니다."
            case .notRecording: "종료할 영상 녹화가 없습니다."
            case .cannotStartWriter(let reason): "영상 녹화를 시작할 수 없습니다: \(reason)"
            case .writerFailed(let reason): "영상 저장에 실패했습니다: \(reason)"
            case .chunkTooLarge(let index, let bytes):
                "영상 조각 \(index + 1)의 크기(\(bytes) bytes)가 Storage 제한을 넘었습니다."
            }
        }
    }

    /// Owned exclusively by the writer queue, including while waiting for delayed audio.
    private final class Chunk: @unchecked Sendable {
        let writer: AVAssetWriter
        let video: AVAssetWriterInput
        let audio: AVAssetWriterInput?
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let url: URL
        let index: Int
        let start: Double
        var end: Double?

        init(url: URL, index: Int, start: Double, firstFrame: CVPixelBuffer,
             orientation: UIInterfaceOrientation, audioSampleRate: Double?) throws {
            self.url = url
            self.index = index
            self.start = start
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            video = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: CVPixelBufferGetWidth(firstFrame),
                AVVideoHeightKey: CVPixelBufferGetHeight(firstFrame),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2_000_000,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoMaxKeyFrameIntervalKey: 60
                ]
            ])
            video.expectsMediaDataInRealTime = true
            video.transform = ARFrameVideoWriter.videoTransform(for: orientation)
            guard writer.canAdd(video) else { throw RecorderError.cannotAddVideoInput }
            writer.add(video)
            if let audioSampleRate {
                let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: audioSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64_000,
                    AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant
                ])
                audio.expectsMediaDataInRealTime = true
                guard writer.canAdd(audio) else { throw RecorderError.cannotAddAudioInput }
                writer.add(audio)
                self.audio = audio
            } else {
                audio = nil
            }
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
            guard writer.startWriting() else {
                throw RecorderError.cannotStartWriter(writer.error?.localizedDescription ?? "알 수 없는 오류")
            }
            writer.startSession(atSourceTime: .zero)
            guard video.isReadyForMoreMediaData, adaptor.append(firstFrame, withPresentationTime: .zero) else {
                writer.cancelWriting()
                throw RecorderError.cannotStartWriter("첫 영상 프레임을 기록하지 못했습니다.")
            }
        }
    }

    private let queue = DispatchQueue(label: "com.cqb.member.video-writer", qos: .userInitiated)
    private let finishedWriters = DispatchGroup()
    private let pendingLock = NSLock()
    private let chunkDuration: TimeInterval
    private let minimumFrameInterval = 1.0 / 30.0
    private var pendingFrameCount = 0
    private var failure: String?
    private var active: Chunk?
    private var closing: [Chunk] = []
    private var bufferedAudio: [CMSampleBuffer] = []
    private var audioWatermark = -Double.infinity
    private var lastAudioTimestamp = -Double.infinity
    private var audioInterrupted = false
    private var audioSampleRate: Double?
    private var latestVideoTimestamp = 0.0
    private var lastAppendedTimestamp = -Double.infinity
    private var outputDirectory: URL?
    private var orientation: UIInterfaceOrientation = .landscapeRight
    private var completedChunks: [Int: URL] = [:]
    private var onChunkReady: (@Sendable (Int, URL) -> Void)?
    private var isFinishing = false
    private var retryScheduled = false

    init(chunkDuration: TimeInterval = ARFrameVideoWriter.targetChunkDuration) {
        self.chunkDuration = chunkDuration
    }

    var failureDescription: String? {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        return failure
    }

    func start(firstFrame: CVPixelBuffer, timestamp: TimeInterval, outputDirectory: URL,
               orientation: UIInterfaceOrientation, audioSampleRate: Double? = nil,
               onChunkReady: @escaping @Sendable (Int, URL) -> Void) throws {
        try queue.sync {
            guard active == nil, closing.isEmpty, !isFinishing else { throw RecorderError.alreadyRecording }
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            self.outputDirectory = outputDirectory
            self.orientation = orientation
            self.audioSampleRate = audioSampleRate
            self.onChunkReady = onChunkReady
            completedChunks = [:]
            bufferedAudio = []
            audioWatermark = -.infinity
            lastAudioTimestamp = -.infinity
            audioInterrupted = false
            setFailure(nil)
            active = try makeChunk(index: 0, frame: firstFrame, timestamp: timestamp)
            latestVideoTimestamp = timestamp
            lastAppendedTimestamp = timestamp
        }
    }

    func append(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        pendingLock.lock()
        guard pendingFrameCount < 2 else { pendingLock.unlock(); return }
        pendingFrameCount += 1
        pendingLock.unlock()
        // Retain the immutable camera buffer until the serial writer queue has consumed it.
        nonisolated(unsafe) let capturedFrame = pixelBuffer
        queue.async { [self] in
            defer { pendingLock.lock(); pendingFrameCount -= 1; pendingLock.unlock() }
            guard let chunk = active, !isFinishing, timestamp > latestVideoTimestamp else { return }
            guard chunk.writer.status == .writing else {
                setFailure(chunk.writer.error?.localizedDescription ?? "영상 인코더 오류")
                return
            }
            latestVideoTimestamp = timestamp
            let size = ((try? FileManager.default.attributesOfItem(atPath: chunk.url.path)[.size]) as? NSNumber)?.intValue ?? 0
            if timestamp - chunk.start >= chunkDuration - 0.000001 || size >= Self.maximumChunkBytes - 2 * 1024 * 1024 {
                chunk.end = timestamp
                closing.append(chunk)
                do {
                    active = try makeChunk(index: chunk.index + 1, frame: capturedFrame, timestamp: timestamp)
                    lastAppendedTimestamp = timestamp
                } catch {
                    active = nil
                    setFailure(error.localizedDescription)
                }
            } else if timestamp - lastAppendedTimestamp >= minimumFrameInterval - 0.001,
                      chunk.video.isReadyForMoreMediaData {
                if chunk.adaptor.append(capturedFrame, withPresentationTime: time(timestamp - chunk.start)) {
                    lastAppendedTimestamp = timestamp
                } else {
                    setFailure(chunk.writer.error?.localizedDescription ?? "영상 프레임 저장 실패")
                }
            }
            drainAudio(upTo: timestamp)
            finishCoveredChunks()
        }
    }

    /// Input timestamps have already been converted from the capture clock to host time.
    func append(audioSampleBuffer: CMSampleBuffer) {
        // The sample is read-only; ownership is retained while it crosses to the writer queue.
        nonisolated(unsafe) let capturedAudio = audioSampleBuffer
        queue.async { [self] in
            guard active != nil, !isFinishing, audioSampleRate != nil else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(capturedAudio).seconds
            guard pts.isFinite else { setFailure("유효하지 않은 오디오 시각입니다."); return }
            // Device-clock conversion can put the next PTS slightly before the previous
            // buffer's calculated end. That is not a duplicate: discarding the entire PCM
            // buffer loses real samples, and AAC then packs the remaining audio together.
            // Use start-time ordering to reject only duplicate or out-of-order callbacks.
            guard pts > lastAudioTimestamp else { return }
            lastAudioTimestamp = pts
            audioInterrupted = false
            audioWatermark = max(audioWatermark, RecordingAudioSamples.endTime(of: capturedAudio))
            bufferedAudio.append(capturedAudio)
            drainAudio(upTo: latestVideoTimestamp)
            finishCoveredChunks()
        }
    }

    /// A queue barrier for callers that supply frames faster than a real-time camera.
    func waitForPendingWrites() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    func markAudioInterrupted() {
        queue.async { [self] in
            audioInterrupted = true
            drainAudio(upTo: latestVideoTimestamp)
            finishCoveredChunks()
        }
    }

    func finish(at timestamp: TimeInterval? = nil,
                completion: @escaping @Sendable (Result<[URL], Error>) -> Void) {
        queue.async { [self] in
            guard !isFinishing else { completion(.failure(RecorderError.notRecording)); return }
            guard let chunk = active else {
                if failureDescription == nil { setFailure(RecorderError.notRecording.localizedDescription) }
                finishRemaining(completion: completion)
                return
            }
            isFinishing = true
            chunk.end = max(timestamp ?? latestVideoTimestamp + minimumFrameInterval, latestVideoTimestamp)
            closing.append(chunk)
            active = nil
            drainForFinish(deadline: Date().addingTimeInterval(2), completion: completion)
        }
    }

    /// Startup cancellation must not publish an incomplete chunk to the upload queue.
    func cancel() {
        queue.sync {
            for chunk in closing + (active.map { [$0] } ?? []) {
                chunk.writer.cancelWriting()
                try? FileManager.default.removeItem(at: chunk.url)
            }
            active = nil
            closing = []
            bufferedAudio = []
            outputDirectory = nil
            onChunkReady = nil
        }
    }

    func discardFinishedCapture() {
        queue.sync {
            guard active == nil, !isFinishing else { return }
            completedChunks = [:]
            bufferedAudio = []
            onChunkReady = nil
            outputDirectory = nil
            setFailure(nil)
        }
    }

    private func makeChunk(index: Int, frame: CVPixelBuffer, timestamp: Double) throws -> Chunk {
        guard let outputDirectory else { throw RecorderError.cannotStartWriter("영상 조각 저장 경로가 없습니다.") }
        let url = outputDirectory.appendingPathComponent(String(format: "chunk_%04d.mp4", index))
        try? FileManager.default.removeItem(at: url)
        return try Chunk(url: url, index: index, start: timestamp, firstFrame: frame,
                         orientation: orientation, audioSampleRate: audioSampleRate)
    }

    private func drainAudio(upTo cutoff: Double) {
        let chunks = closing + (active.map { [$0] } ?? [])
        while let buffer = bufferedAudio.first {
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard pts < cutoff else { return }
            guard let chunk = chunks.first(where: { ($0.end ?? cutoff) > pts }) else {
                bufferedAudio.removeFirst()
                continue
            }
            let end = min(chunk.end ?? cutoff, cutoff)
            guard let portion = RecordingAudioSamples.slice(buffer, from: chunk.start, to: end) else {
                bufferedAudio.removeFirst()
                continue
            }
            if let audio = chunk.audio {
                guard audio.isReadyForMoreMediaData else {
                    if chunk.writer.status == .failed {
                        setFailure(chunk.writer.error?.localizedDescription ?? "오디오 인코더 오류")
                        bufferedAudio.removeFirst()
                        continue
                    }
                    scheduleAudioRetry()
                    return
                }
                guard let adjusted = RecordingAudioSamples.retime(portion, convert: { CMTimeSubtract($0, time(chunk.start)) }),
                      audio.append(adjusted) else {
                    setFailure(chunk.writer.error?.localizedDescription ?? "오디오 프레임 저장 실패")
                    bufferedAudio.removeFirst()
                    continue
                }
            }
            if let remainder = RecordingAudioSamples.slice(buffer, from: end, to: RecordingAudioSamples.endTime(of: buffer)) {
                bufferedAudio[0] = remainder
            } else {
                bufferedAudio.removeFirst()
            }
        }
    }

    private func scheduleAudioRetry() {
        guard !retryScheduled, !isFinishing else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + 0.01) { [self] in
            retryScheduled = false
            guard !isFinishing else { return }
            drainAudio(upTo: latestVideoTimestamp)
            finishCoveredChunks()
        }
    }

    private func finishCoveredChunks() {
        while let chunk = closing.first, let end = chunk.end {
            let pendingBeforeEnd = bufferedAudio.first.map { CMSampleBufferGetPresentationTimeStamp($0).seconds < end } ?? false
            // Bound the number of open encoders even if capture stops delivering audio without
            // an interruption notification. Such late audio is a permitted gap in the contract.
            let audioTimedOut = latestVideoTimestamp - end > 2
            guard !pendingBeforeEnd,
                  audioSampleRate == nil || audioInterrupted || audioWatermark >= end || audioTimedOut else { return }
            closing.removeFirst()
            finishChunk(chunk)
        }
    }

    private func drainForFinish(deadline: Date,
                                completion: @escaping @Sendable (Result<[URL], Error>) -> Void) {
        let end = closing.last?.end ?? latestVideoTimestamp
        drainAudio(upTo: end)
        let hasPendingAudio = bufferedAudio.first.map { CMSampleBufferGetPresentationTimeStamp($0).seconds < end } ?? false
        if hasPendingAudio, Date() < deadline {
            queue.asyncAfter(deadline: .now() + 0.01) { [self] in
                drainForFinish(deadline: deadline, completion: completion)
            }
            return
        }
        if hasPendingAudio { setFailure("오디오 인코더 응답 시간이 초과되었습니다.") }
        bufferedAudio = []
        finishRemaining(completion: completion)
    }

    private func finishRemaining(completion: @escaping @Sendable (Result<[URL], Error>) -> Void) {
        isFinishing = true
        closing.forEach(finishChunk)
        closing = []
        finishedWriters.notify(queue: queue) { [self] in
            let result: Result<[URL], Error>
            if let failure = failureDescription { result = .failure(RecorderError.writerFailed(failure)) }
            else { result = .success(completedChunks.keys.sorted().compactMap { completedChunks[$0] }) }
            isFinishing = false
            onChunkReady = nil
            outputDirectory = nil
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func finishChunk(_ chunk: Chunk) {
        if let end = chunk.end { chunk.writer.endSession(atSourceTime: time(end - chunk.start)) }
        chunk.video.markAsFinished()
        chunk.audio?.markAsFinished()
        finishedWriters.enter()
        chunk.writer.finishWriting { [self] in
            queue.async { [self] in
                if chunk.writer.status == .completed {
                    let bytes = ((try? FileManager.default.attributesOfItem(atPath: chunk.url.path)[.size]) as? NSNumber)?.intValue ?? 0
                    if bytes > 0, bytes <= Self.maximumChunkBytes {
                        completedChunks[chunk.index] = chunk.url
                        onChunkReady?(chunk.index, chunk.url)
                    } else {
                        setFailure(RecorderError.chunkTooLarge(index: chunk.index, bytes: bytes).localizedDescription)
                    }
                } else { setFailure(chunk.writer.error?.localizedDescription ?? "영상 인코더 오류") }
                finishedWriters.leave()
            }
        }
    }

    private func setFailure(_ message: String?) {
        pendingLock.lock()
        if failure == nil || message == nil { failure = message }
        pendingLock.unlock()
    }

    private func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 1_000_000_000) }

    private static func videoTransform(for orientation: UIInterfaceOrientation) -> CGAffineTransform {
        switch orientation {
        case .portrait: CGAffineTransform(rotationAngle: .pi / 2)
        case .portraitUpsideDown: CGAffineTransform(rotationAngle: -.pi / 2)
        case .landscapeLeft: CGAffineTransform(rotationAngle: .pi)
        default: .identity
        }
    }
}
