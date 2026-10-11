import SwiftUI
import CQBDesignSystem

struct RootView: View {
    @Environment(MemberStore.self) private var store
    private var floorPlan: UIImage? {
        store.trainingMap.flatMap { UIImage(contentsOfFile: $0.imageURL.path) }
    }

    var body: some View {
        Group {
            switch store.phase {
            case .join:
                SessionJoinView { pin, name in
                    store.join(pin: pin, memberName: name)
                }
            case .setup:
                if let floorPlan {
                    StartPositionSetupView(
                        floorPlan: floorPlan,
                        startPoint: store.startPoint,
                        directionPoint: store.directionPoint
                    ) { start, direction in
                        store.confirmPosition(start: start, direction: direction)
                    }
                } else {
                    ContentUnavailableView("도면을 불러올 수 없습니다", systemImage: "map")
                }
            case .waiting, .recording, .saving, .correcting:
                TrainingRecordingView(
                    phase: store.phase,
                    startedAt: store.recordingStartedAt,
                    onFinish: { Task { await store.finishRecording() } },
                    onStart: { Task { await store.startRecording() } },
                    onReset: { store.resetPosition() },
                    cameraService: store.cameraService,
                    onStopRecording: { await store.finishRecording() }
                )
            case .saved:
                RecordingSaveTestView(recordingURL: store.savedRecordingURL,
                    raw: store.rawTrack, correction: store.correction, mapImage: floorPlan,
                    files: store.recordingFiles, filesSaved: store.filesSaved,
                    onHome: { store.returnToJoin() },
                    onRetry: { Task { await store.retrySaving() } }) {
                    store.startUploading()
                }
            case .uploading:
                RecordingUploadView(
                    progress: store.uploadProgress,
                    isComplete: store.isUploadComplete,
                    onHome: { store.returnToJoin() }
                )
                .task { await store.simulateUpload() }
            }
        }
        .alert(
            "기록 안내",
            isPresented: Binding(
                get: { store.recordingError != nil },
                set: { if !$0 { store.clearRecordingError() } }
            )
        ) {
            Button("확인", role: .cancel) { store.clearRecordingError() }
        } message: {
            Text(store.recordingError ?? "녹화 중 문제가 발생했습니다.")
        }
    }
}
