import ARKit
import SwiftUI

struct CameraPreviewView: View {
    let service: ARRecordingService
    let isRecording: Bool
    let isWaiting: Bool
    var onStopRecording: () async -> Void
    var onAvailabilityChange: (Bool) -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ARCameraSurface(session: service.session)
            .ignoresSafeArea()
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
