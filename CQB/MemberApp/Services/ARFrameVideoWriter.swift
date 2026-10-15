import AVFoundation
import UIKit

nonisolated final class ARFrameVideoWriter: @unchecked Sendable {
    static let targetChunkDuration: TimeInterval = 30
    static let maximumChunkBytes = 20 * 1024 * 1024

    enum RecorderError: LocalizedError {
        case alreadyRecording
        case cannotAddVideoInput
        case cannotStartWriter(String)
        case notRecording
        case writerFailed(String)
        case chunkTooLarge(index: Int, bytes: Int)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "이미 영상을 녹화하고 있습니다."
            case .cannotAddVideoInput: return "영상 인코더 입력을 만들 수 없습니다."
            case .cannotStartWriter(let reason): return "영상 녹화를 시작할 수 없습니다: \(reason)"
            case .notRecording: return "종료할 영상 녹화가 없습니다."
            case .writerFailed(let reason): return "영상 저장에 실패했습니다: \(reason)"
            case .chunkTooLarge(let index, let bytes):
                return "영상 조각 \(index + 1)의 크기(\(bytes) bytes)가 Storage 제한을 넘었습니다."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.cqb.member.video-writer", qos: .userInitiated)
    private let finishedWriters = DispatchGroup()
    private let pendingLock = NSLock()
    private let maximumPendingFrames = 2
    private let minimumFrameInterval = 1.0 / 30.0

    private var pendingFrameCount = 0
    private var failure: String?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputDirectory: URL?
    private var orientation: UIInterfaceOrientation = .landscapeRight
    private var chunkStartedAt = 0.0
    private var lastAppendedTimestamp = -Double.infinity
    private var lastSizeCheckTimestamp = -Double.infinity
    private var nextChunkIndex = 0
    private var completedChunks: [Int: URL] = [:]
    private var onChunkReady: (@Sendable (Int, URL) -> Void)?

    var failureDescription: String? {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        return failure
    }

    func start(
        firstFrame: CVPixelBuffer,
        timestamp: TimeInterval,
        outputDirectory: URL,
        orientation: UIInterfaceOrientation,
        onChunkReady: @escaping @Sendable (Int, URL) -> Void
    ) throws {
        try queue.sync {
            guard writer == nil else { throw RecorderError.alreadyRecording }
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            self.outputDirectory = outputDirectory
            self.orientation = orientation
            self.onChunkReady = onChunkReady
            nextChunkIndex = 0
            completedChunks = [:]
            setFailure(nil)
            try startWriter(firstFrame: firstFrame, timestamp: timestamp)
        }
    }

    func append(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        pendingLock.lock()
        guard pendingFrameCount < maximumPendingFrames else {
            pendingLock.unlock()
            return
        }
        pendingFrameCount += 1
        pendingLock.unlock()

        queue.async { [self] in
            defer {
                pendingLock.lock()
                pendingFrameCount -= 1
                pendingLock.unlock()
            }
            guard let writer else { return }
            if writer.status == .failed {
                setFailure(writer.error?.localizedDescription ?? "영상 인코더 오류")
                return
            }

            let chunkDuration = timestamp - chunkStartedAt
            let shouldCheckSize = timestamp - lastSizeCheckTimestamp >= 0.5
            let isNearSizeLimit = shouldCheckSize && currentFileSize >= Self.maximumChunkBytes - 2 * 1024 * 1024
            if chunkDuration >= Self.targetChunkDuration || isNearSizeLimit {
                lastSizeCheckTimestamp = timestamp
                rotateWriter(firstFrame: pixelBuffer, timestamp: timestamp)
                return
            }
            if shouldCheckSize { lastSizeCheckTimestamp = timestamp }
            append(pixelBuffer: pixelBuffer, timestamp: timestamp, to: writer)
        }
    }

    func finish(completion: @escaping @Sendable (Result<[URL], Error>) -> Void) {
        queue.async { [self] in
            if let writer, let input, let url = currentOutputURL {
                finishWriter(writer, input: input, url: url, index: nextChunkIndex)
                self.writer = nil
                self.input = nil
                self.adaptor = nil
            } else if failure == nil {
                setFailure(RecorderError.notRecording.localizedDescription)
            }

            finishedWriters.notify(queue: queue) { [self] in
                let result: Result<[URL], Error>
                if let failure {
                    result = .failure(RecorderError.writerFailed(failure))
                } else {
                    result = .success(completedChunks.keys.sorted().compactMap { completedChunks[$0] })
                }
                resetActiveWriterState()
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    func discardFinishedCapture() {
        queue.sync {
            guard writer == nil else { return }
            completedChunks.removeAll()
            outputDirectory = nil
            onChunkReady = nil
            nextChunkIndex = 0
            setFailure(nil)
        }
    }

    private var currentOutputURL: URL? {
        guard let outputDirectory else { return nil }
        return outputDirectory.appendingPathComponent(String(format: "chunk_%04d.mp4", nextChunkIndex))
    }

    private var currentFileSize: Int {
        guard let currentOutputURL,
              let values = try? currentOutputURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return 0 }
        return size
    }

    private func startWriter(firstFrame: CVPixelBuffer, timestamp: TimeInterval) throws {
        guard let outputURL = currentOutputURL else {
            throw RecorderError.cannotStartWriter("영상 조각 저장 경로가 없습니다.")
        }
        try? FileManager.default.removeItem(at: outputURL)
        let width = CVPixelBufferGetWidth(firstFrame)
        let height = CVPixelBufferGetHeight(firstFrame)
        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = Self.videoTransform(for: orientation)
        guard assetWriter.canAdd(videoInput) else { throw RecorderError.cannotAddVideoInput }
        assetWriter.add(videoInput)

        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: nil
        )
        guard assetWriter.startWriting() else {
            throw RecorderError.cannotStartWriter(assetWriter.error?.localizedDescription ?? "알 수 없는 오류")
        }
        assetWriter.startSession(atSourceTime: .zero)
        guard videoInput.isReadyForMoreMediaData,
              pixelAdaptor.append(firstFrame, withPresentationTime: .zero) else {
            assetWriter.cancelWriting()
            throw RecorderError.cannotStartWriter("첫 영상 프레임을 기록하지 못했습니다.")
        }

        writer = assetWriter
        input = videoInput
        adaptor = pixelAdaptor
        chunkStartedAt = timestamp
        lastAppendedTimestamp = timestamp
        lastSizeCheckTimestamp = timestamp
    }

    private func append(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, to writer: AVAssetWriter) {
        guard writer.status == .writing,
              let input, input.isReadyForMoreMediaData,
              let adaptor else { return }
        let elapsed = timestamp - chunkStartedAt
        guard elapsed >= 0, timestamp - lastAppendedTimestamp >= minimumFrameInterval - 0.001 else { return }
        let presentationTime = CMTime(seconds: elapsed, preferredTimescale: 600)
        if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            lastAppendedTimestamp = timestamp
        } else {
            setFailure(writer.error?.localizedDescription ?? "영상 프레임 저장 실패")
        }
    }

    private func rotateWriter(firstFrame: CVPixelBuffer, timestamp: TimeInterval) {
        guard let currentWriter = writer, let currentInput = input, let currentURL = currentOutputURL else {
            setFailure("영상 조각을 전환할 수 없습니다.")
            return
        }
        finishWriter(currentWriter, input: currentInput, url: currentURL, index: nextChunkIndex)
        writer = nil
        input = nil
        adaptor = nil
        nextChunkIndex += 1
        do {
            try startWriter(firstFrame: firstFrame, timestamp: timestamp)
        } catch {
            setFailure(error.localizedDescription)
        }
    }

    private func finishWriter(_ writer: AVAssetWriter, input: AVAssetWriterInput, url: URL, index: Int) {
        input.markAsFinished()
        finishedWriters.enter()
        writer.finishWriting { [self] in
            queue.async { [self] in
                if writer.status == .completed {
                    let bytes: Int
                    do { bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
                    catch { bytes = 0 }
                    if bytes > 0 && bytes <= Self.maximumChunkBytes {
                        completedChunks[index] = url
                        onChunkReady?(index, url)
                    } else {
                        setFailure(RecorderError.chunkTooLarge(index: index, bytes: bytes).localizedDescription)
                    }
                } else {
                    setFailure(writer.error?.localizedDescription ?? "영상 인코더 오류")
                }
                finishedWriters.leave()
            }
        }
    }

    private func setFailure(_ message: String?) {
        pendingLock.lock()
        failure = message
        pendingLock.unlock()
    }

    private func resetActiveWriterState() {
        writer = nil
        input = nil
        adaptor = nil
        outputDirectory = nil
        onChunkReady = nil
        chunkStartedAt = 0
        lastAppendedTimestamp = -Double.infinity
        lastSizeCheckTimestamp = -Double.infinity
    }

    private static func videoTransform(for orientation: UIInterfaceOrientation) -> CGAffineTransform {
        switch orientation {
        case .portrait: return CGAffineTransform(rotationAngle: .pi / 2)
        case .portraitUpsideDown: return CGAffineTransform(rotationAngle: -.pi / 2)
        case .landscapeLeft: return CGAffineTransform(rotationAngle: .pi)
        case .landscapeRight: return .identity
        default: return .identity
        }
    }
}
