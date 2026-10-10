import AVFoundation
import UIKit

nonisolated final class ARFrameVideoWriter: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case alreadyRecording
        case cannotAddVideoInput
        case cannotStartWriter(String)
        case notRecording
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "이미 영상을 녹화하고 있습니다."
            case .cannotAddVideoInput: return "영상 인코더 입력을 만들 수 없습니다."
            case .cannotStartWriter(let reason): return "영상 녹화를 시작할 수 없습니다: \(reason)"
            case .notRecording: return "종료할 영상 녹화가 없습니다."
            case .writerFailed(let reason): return "영상 저장에 실패했습니다: \(reason)"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.cqb.member.video-writer", qos: .userInitiated)
    private let pendingLock = NSLock()
    private var pendingFrameCount = 0
    private let maximumPendingFrames = 2
    private let minimumFrameInterval = 1.0 / 30.0

    private var failure: String?
    var failureDescription: String? {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        return failure
    }

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var firstTimestamp = 0.0
    private var lastAppendedTimestamp = -Double.infinity

    func start(
        firstFrame: CVPixelBuffer,
        timestamp: TimeInterval,
        outputURL: URL,
        orientation: UIInterfaceOrientation
    ) throws {
        try queue.sync {
            guard writer == nil else { throw RecorderError.alreadyRecording }

            let width = CVPixelBufferGetWidth(firstFrame)
            let height = CVPixelBufferGetHeight(firstFrame)
            let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            let pixelsPerFrame = width * height
            let bitrate = min(max(pixelsPerFrame * 3, 3_000_000), 8_000_000)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
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

            writer = assetWriter
            input = videoInput
            adaptor = pixelAdaptor
            self.outputURL = outputURL
            firstTimestamp = timestamp
            pendingLock.lock()
            failure = nil
            pendingLock.unlock()
            guard videoInput.isReadyForMoreMediaData,
                  pixelAdaptor.append(firstFrame, withPresentationTime: .zero) else {
                assetWriter.cancelWriting()
                reset()
                throw RecorderError.cannotStartWriter("첫 영상 프레임을 기록하지 못했습니다.")
            }
            lastAppendedTimestamp = 0
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
                pendingLock.lock()
                failure = writer.error?.localizedDescription ?? "영상 인코더 오류"
                pendingLock.unlock()
                return
            }
            guard writer.status == .writing,
                  let input, input.isReadyForMoreMediaData,
                  let adaptor else { return }

            let elapsed = timestamp - firstTimestamp
            guard elapsed >= 0,
                  elapsed-lastAppendedTimestamp >= minimumFrameInterval-0.001 else { return }
            let presentationTime = CMTime(seconds: elapsed, preferredTimescale: 600)
            if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                lastAppendedTimestamp = elapsed
            } else {
                pendingLock.lock()
                failure = writer.error?.localizedDescription ?? "영상 프레임 저장 실패"
                pendingLock.unlock()
            }
        }
    }

    func finish(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        queue.async { [self] in
            guard let writer, let input, let outputURL else {
                DispatchQueue.main.async { completion(.failure(RecorderError.notRecording)) }
                return
            }
            guard writer.status == .writing, failureDescription == nil else {
                let error = RecorderError.writerFailed(failureDescription ?? writer.error?.localizedDescription ?? "영상 인코더 오류")
                if writer.status == .writing { writer.cancelWriting() }
                reset()
                completion(.failure(error))
                return
            }
            input.markAsFinished()
            writer.finishWriting { [self] in
                let result: Result<URL, Error>
                if writer.status == .completed {
                    result = .success(outputURL)
                } else {
                    result = .failure(RecorderError.writerFailed(writer.error?.localizedDescription ?? "알 수 없는 오류"))
                }
                queue.async { [self] in
                    reset()
                    DispatchQueue.main.async { completion(result) }
                }
            }
        }
    }

    private func reset() {
        writer = nil
        input = nil
        adaptor = nil
        outputURL = nil
        firstTimestamp = 0
        lastAppendedTimestamp = -Double.infinity
    }

    private static func videoTransform(for orientation: UIInterfaceOrientation) -> CGAffineTransform {
        // AR capturedImage의 기준은 UIInterfaceOrientation.landscapeRight이다.
        // UIDeviceOrientation의 가로 방향 이름과 혼동하지 않는다.
        switch orientation {
        case .portrait: return CGAffineTransform(rotationAngle: .pi / 2)
        case .portraitUpsideDown: return CGAffineTransform(rotationAngle: -.pi / 2)
        case .landscapeLeft: return CGAffineTransform(rotationAngle: .pi)
        case .landscapeRight: return .identity
        default: return .identity
        }
    }
}
