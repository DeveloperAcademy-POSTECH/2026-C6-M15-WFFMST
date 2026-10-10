import AVFoundation
import Foundation

/// Capture session의 구성과 실행은 전용 직렬 큐에서만 수행한다.
nonisolated final class CameraPreviewService: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "MemberApp.camera.capture")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var isConfigured = false
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuation: CheckedContinuation<URL, Error>?

    func start() async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                do {
                    if !isConfigured { try configure() }
                    if !session.isRunning { session.startRunning() }
                    continuation.resume(returning: session.isRunning ? nil : "카메라를 시작할 수 없습니다.")
                } catch {
                    continuation.resume(returning: "후면 카메라를 사용할 수 없습니다.")
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            // 녹화 중에는 화면 생명주기만으로 세션을 내리지 않는다.
            guard !movieOutput.isRecording else { return }
            if session.isRunning { session.stopRunning() }
        }
    }

    func setVideoRotationAngle(_ angle: CGFloat) {
        queue.async { [self] in
            guard let connection = movieOutput.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }

    /// 녹화 delegate가 실제 시작을 알릴 때까지 기다린다.
    func startRecording(to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard session.isRunning else {
                    continuation.resume(throwing: CameraError.sessionNotRunning)
                    return
                }
                guard !movieOutput.isRecording, startContinuation == nil else {
                    continuation.resume(throwing: CameraError.alreadyRecording)
                    return
                }

                startContinuation = continuation
                movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    /// 파일 기록 종료 delegate가 성공을 확인한 URL을 반환한다.
    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            queue.async { [self] in
                guard movieOutput.isRecording, stopContinuation == nil else {
                    continuation.resume(throwing: CameraError.notRecording)
                    return
                }
                stopContinuation = continuation
                movieOutput.stopRecording()
            }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input), session.canAddOutput(movieOutput) else {
            throw CameraError.unavailable
        }
        session.addInput(input)
        session.addOutput(movieOutput)
        isConfigured = true
    }

    private enum CameraError: LocalizedError {
        case unavailable
        case sessionNotRunning
        case alreadyRecording
        case notRecording

        var errorDescription: String? {
            switch self {
            case .unavailable: "후면 카메라를 사용할 수 없습니다."
            case .sessionNotRunning: "카메라가 준비되지 않아 녹화를 시작할 수 없습니다."
            case .alreadyRecording: "이미 녹화 중입니다."
            case .notRecording: "진행 중인 녹화를 찾을 수 없습니다."
            }
        }
    }
}

extension CameraPreviewService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        queue.async { [self] in
            guard let continuation = startContinuation else { return }
            startContinuation = nil
            continuation.resume()
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        queue.async { [self] in
            startContinuation?.resume(throwing: error ?? CameraError.notRecording)
            startContinuation = nil

            if let error {
                stopContinuation?.resume(throwing: error)
            } else {
                stopContinuation?.resume(returning: outputFileURL)
            }
            stopContinuation = nil
        }
    }
}
