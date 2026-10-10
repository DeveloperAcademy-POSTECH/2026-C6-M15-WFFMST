import AVFoundation
import SwiftUI
import CQBDesignSystem

/// 라이브 미리보기만 제공한다. 영상 파일 녹화와 ARKit 추적은 별도 연동 대상이다.
struct CameraPreviewView: View {
    var onAvailabilityChange: (Bool) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var service = CameraPreviewService()
    @State private var message: String?
    @State private var needsSettings = false
    @State private var isReady = false

    var body: some View {
        ZStack {
            DSColor.background
            CameraPreviewLayer(session: service.session)
            if let message {
                VStack(spacing: 12) {
                    Text(message).multilineTextAlignment(.center)
                    if needsSettings {
                        Button("설정에서 카메라 허용") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
                .font(DSTypography.bodySmall)
                .foregroundStyle(DSColor.white)
                .tint(DSColor.main)
                .padding(20)
                .background(DSColor.area1, in: RoundedRectangle(cornerRadius: 4))
                .padding(24)
            } else if !isReady {
                ProgressView().tint(DSColor.white)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                service.stop()
                isReady = false
                return
            }
            await startCamera()
        }
        .onChange(of: isReady) { _, ready in onAvailabilityChange(ready) }
        .onDisappear {
            service.stop()
            onAvailabilityChange(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: service.session)) { _ in
            isReady = false
            message = "카메라 사용이 일시 중단되었습니다."
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.interruptionEndedNotification, object: service.session)) { _ in
            isReady = true
            message = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: service.session)) { _ in
            isReady = false
            message = "카메라 오류가 발생했습니다. 화면에 다시 진입해주세요."
        }
    }

    private func startCamera() async {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            message = "카메라 미리보기는 실제 iPhone에서 확인해주세요."
            return
        }
        needsSettings = false
        message = nil
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let authorized: Bool
        if status == .notDetermined {
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            authorized = status == .authorized
        }
        guard !Task.isCancelled else { return }
        guard authorized else {
            needsSettings = AVCaptureDevice.authorizationStatus(for: .video) == .denied
            message = "카메라 접근 권한이 필요합니다."
            return
        }
        let error = await service.start()
        guard !Task.isCancelled else {
            service.stop()
            return
        }
        message = error
        isReady = error == nil
    }
}

private struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewSurface, context: Context) {
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: PreviewSurface, coordinator: ()) {
        view.previewLayer.session = nil
    }

    final class PreviewSurface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection = previewLayer.connection,
                  let orientation = window?.windowScene?.interfaceOrientation else { return }
            let angle: CGFloat
            switch orientation {
            case .landscapeLeft: angle = 180
            case .landscapeRight: angle = 0
            case .portraitUpsideDown: angle = 270
            default: angle = 90
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}
