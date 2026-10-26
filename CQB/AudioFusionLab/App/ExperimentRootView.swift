import SwiftUI

struct ExperimentRootView: View {
    @Environment(ExperimentStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .setup:
                    ExperimentSetupView()
                case .preparing, .ready:
                    CaptureReadyView()
                case .recording:
                    ExperimentRecordingView()
                case .analyzing:
                    AnalysisProgressView()
                case .completed:
                    ExperimentResultView()
                }
            }
            .navigationTitle("Audio Fusion Lab")
        }
    }
}
