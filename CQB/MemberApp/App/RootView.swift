import SwiftUI
import CQBDesignSystem

struct RootView: View {
    @Environment(MemberStore.self) private var store
    // 목업 도면. 실제 연동 시 세션에서 내려받은 도면을 전달한다.
    private let floorPlan = UIImage(named: "TrainingFloorPlan")

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
            case .waiting, .recording:
                TrainingRecordingView(
                    phase: store.phase,
                    startedAt: store.recordingStartedAt,
                    onFinish: { store.startUploading() },
                    onStart: { store.startRecording() },
                    onReset: { store.resetPosition() }
                )
            case .uploading:
                RecordingUploadView(
                    progress: store.uploadProgress,
                    isComplete: store.isUploadComplete,
                    onHome: { store.returnToJoin() }
                )
                .task { await store.simulateUpload() }
            }
        }
    }
}
