@preconcurrency import ARKit
@preconcurrency import AVFoundation
import CoreMedia
import Observation

/// ARKit이 소유한 카메라 세션에서 오디오 sample buffer를 받아 분석용 CAF로 보존한다.
@MainActor @Observable
final class ARAudioCaptureService: NSObject, @preconcurrency ARSessionDelegate {
    enum CaptureError: LocalizedError {
        case unsupportedDevice
        case cameraPermissionDenied
        case microphonePermissionDenied
        case notReady
        case alreadyRecording
        case noAudio
        case writerSetup(String)
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedDevice: "이 기기는 ARKit 동선 추적을 지원하지 않습니다."
            case .cameraPermissionDenied: "설정에서 카메라 접근을 허용해주세요."
            case .microphonePermissionDenied: "설정에서 마이크 접근을 허용해주세요."
            case .notReady: "ARKit 카메라 프레임이 준비되지 않았습니다."
            case .alreadyRecording: "이미 오디오를 기록하고 있습니다."
            case .noAudio: "마이크 오디오를 받지 못했습니다."
            case .writerSetup(let reason): "오디오 파일을 시작하지 못했습니다: \(reason)"
            case .writerFailed(let reason): "오디오 파일 저장에 실패했습니다: \(reason)"
            }
        }
    }

    let session = ARSession()
    private(set) var isReady = false
    private(set) var isRecording = false
    private(set) var statusMessage = "ARKit 준비 전"
    private(set) var fatalErrorDescription: String?

    private var outputURL: URL?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var recordingOriginARTime: TimeInterval?
    private var firstAudioPresentationTime: CMTime?
    private var lastAudioEndTime: CMTime?
    private var sampleRate = 0.0
    private var channelCount = 0

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    func prepare() async throws {
        guard ARWorldTrackingConfiguration.isSupported else { throw CaptureError.unsupportedDevice }
        guard await requestPermission(for: .video) else { throw CaptureError.cameraPermissionDenied }
        guard await requestPermission(for: .audio) else { throw CaptureError.microphonePermissionDenied }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)

        fatalErrorDescription = nil
        isReady = false
        statusMessage = "ARKit 카메라와 마이크 준비 중"
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.providesAudioData = true
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func startRecording(to url: URL) throws {
        guard !isRecording else { throw CaptureError.alreadyRecording }
        guard isReady, let frame = session.currentFrame else { throw CaptureError.notReady }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        outputURL = url
        writer = nil
        writerInput = nil
        recordingOriginARTime = frame.timestamp
        firstAudioPresentationTime = nil
        lastAudioEndTime = nil
        sampleRate = 0
        channelCount = 0
        fatalErrorDescription = nil
        isRecording = true
        statusMessage = "오디오 기록 중"
    }

    func stopRecording() async throws -> AudioCaptureSummary {
        guard isRecording else {
            if let fatalErrorDescription { throw CaptureError.writerFailed(fatalErrorDescription) }
            throw CaptureError.noAudio
        }
        isRecording = false

        guard let writer, let writerInput,
              let recordingOriginARTime,
              let firstAudioPresentationTime,
              let lastAudioEndTime else {
            throw CaptureError.noAudio
        }

        writerInput.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            throw CaptureError.writerFailed(writer.error?.localizedDescription ?? "알 수 없는 저장 오류")
        }

        let firstPTS = firstAudioPresentationTime.seconds
        let duration = max(0, lastAudioEndTime.seconds - firstPTS)
        let summary = AudioCaptureSummary(
            recordingOriginARTime: recordingOriginARTime,
            firstAudioPresentationTime: firstPTS,
            audioStartOffsetSeconds: firstPTS - recordingOriginARTime,
            audioDurationSeconds: duration,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
        resetWriter()
        statusMessage = "오디오 저장 완료"
        return summary
    }

    func currentRecordingTime() -> TimeInterval? {
        guard let origin = recordingOriginARTime, let timestamp = session.currentFrame?.timestamp else { return nil }
        return max(0, timestamp - origin)
    }

    func stopSession() {
        guard !isRecording else { return }
        session.pause()
        isReady = false
        statusMessage = "ARKit 중지"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isRecording else { return }
        switch frame.camera.trackingState {
        case .normal:
            isReady = true
            statusMessage = "녹음 준비 완료"
        case .limited:
            isReady = false
            statusMessage = "카메라 추적 안정화 중"
        case .notAvailable:
            isReady = false
            statusMessage = "ARKit 추적을 사용할 수 없습니다."
        }
    }

    func session(_ session: ARSession, didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }
        do {
            if writer == nil {
                try startWriter(with: audioSampleBuffer)
            }
            guard let writer, let writerInput else { return }
            if writer.status == .failed {
                throw CaptureError.writerFailed(writer.error?.localizedDescription ?? "오디오 writer 오류")
            }
            if writerInput.isReadyForMoreMediaData {
                guard writerInput.append(audioSampleBuffer) else {
                    throw CaptureError.writerFailed(writer.error?.localizedDescription ?? "오디오 buffer 저장 실패")
                }
                updateLastAudioEnd(using: audioSampleBuffer)
            }
        } catch {
            fatalErrorDescription = error.localizedDescription
            isRecording = false
            statusMessage = "오디오 저장 실패"
            writer?.cancelWriting()
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        fatalErrorDescription = "ARKit 세션이 중단되었습니다."
        isReady = false
        if isRecording { statusMessage = "녹음 중단" }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        fatalErrorDescription = error.localizedDescription
        isReady = false
        if isRecording { statusMessage = "ARKit 오류로 녹음 중단" }
    }

    private func startWriter(with sampleBuffer: CMSampleBuffer) throws {
        guard let outputURL,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw CaptureError.writerSetup("오디오 포맷 또는 저장 경로가 없습니다.")
        }
        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .caf)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: formatDescription
        )
        input.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(input) else {
            throw CaptureError.writerSetup("CAF 오디오 입력을 추가할 수 없습니다.")
        }
        assetWriter.add(input)
        guard assetWriter.startWriting() else {
            throw CaptureError.writerSetup(assetWriter.error?.localizedDescription ?? "writer 시작 오류")
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        assetWriter.startSession(atSourceTime: presentationTime)

        if let description = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
            sampleRate = description.pointee.mSampleRate
            channelCount = Int(description.pointee.mChannelsPerFrame)
        }
        firstAudioPresentationTime = presentationTime
        writer = assetWriter
        writerInput = input
    }

    private func updateLastAudioEnd(using sampleBuffer: CMSampleBuffer) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        if duration.isValid, duration.isNumeric {
            lastAudioEndTime = presentationTime + duration
        } else if sampleRate > 0 {
            let frames = CMSampleBufferGetNumSamples(sampleBuffer)
            lastAudioEndTime = presentationTime + CMTime(seconds: Double(frames) / sampleRate, preferredTimescale: 1_000_000_000)
        } else {
            lastAudioEndTime = presentationTime
        }
    }

    private func resetWriter() {
        outputURL = nil
        writer = nil
        writerInput = nil
        recordingOriginARTime = nil
        firstAudioPresentationTime = nil
        lastAudioEndTime = nil
    }

    private func requestPermission(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted: false
        @unknown default: false
        }
    }
}
