import ARKit
import SwiftUI
import CQBDesignSystem

struct CameraPreviewView: View {
    let service: ARRecordingService
    let isRecording: Bool
    let isWaiting: Bool
    var onStopRecording: () async -> Void
    var onAvailabilityChange: (Bool) -> Void
    @Environment(\.scenePhase) private var scenePhase

    private var guidanceMessage: String? {
        if let error = service.fatalError { return error }
        if isRecording { return service.trackingWarning }
        if isWaiting && !service.isReady { return service.statusMessage }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ARCameraSurface(session: service.session)
                    .ignoresSafeArea()
                if let guidanceMessage {
                    VStack {
                        Spacer()
                        Text(guidanceMessage)
                            .font(DSTypography.body)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding(24)
                            .background(DSColor.area1)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSColor.area3))
                            .opacity(0.94)
                            .frame(maxWidth: min(650, max(0, geometry.size.width - 48)))
                        if isWaiting, service.fatalError != nil {
                            Button("카메라 다시 준비") { Task { await service.start() } }
                        }
                        Spacer()
                    }
                }
            }
            .task { await service.start() }
            .onChange(of: service.isReady, initial: true) { _, ready in onAvailabilityChange(ready) }
            .onChange(of: service.fatalError) { _, error in
                guard error != nil else { return }
                Task {
                    if isRecording { await onStopRecording() }
                    service.stop()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                Task {
                    if phase == .active { await service.start() }
                    else {
                        if isRecording { await onStopRecording() }
                        service.stop()
                    }
                }
            }
            .onDisappear { service.stop() }
        }
    }
}

private struct ARCameraSurface: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
