import AVFoundation
import Foundation

/// Capture session의 구성과 실행은 전용 직렬 큐에서만 수행한다.
nonisolated final class CameraPreviewService: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "MemberApp.camera.preview")
    private var isConfigured = false

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
            if session.isRunning { session.stopRunning() }
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
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)
        isConfigured = true
    }

    private enum CameraError: Error { case unavailable }
}
