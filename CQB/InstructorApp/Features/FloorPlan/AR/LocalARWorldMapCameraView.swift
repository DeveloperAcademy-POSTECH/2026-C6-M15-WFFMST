import ARKit
import SwiftUI

struct LocalARWorldMapCameraView: UIViewRepresentable {
    let previewSession: AnyObject

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = true
        if let session = previewSession as? ARSession { view.session = session }
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        if let session = previewSession as? ARSession, view.session !== session {
            view.session = session
        }
    }
}
