import SwiftUI
import CQBDesignSystem

struct RootView: View {
    @Environment(MemberStore.self) private var store
    @Environment(MemberDemoMode.self) private var demoMode
    var demoControl: MemberDemoSessionControl?

    private var floorPlan: UIImage? {
        store.trainingMap.flatMap { UIImage(contentsOfFile: $0.imageURL.path) }
    }

    var body: some View {
        destination
        .safeAreaInset(edge: .top, spacing: 0) {
            if demoMode.isActive {
                demoBanner
            }
        }
        .alert(
            "기록 안내",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.clearRecordingError() } }
            )
        ) {
            if store.canRetryRecordingStart {
                Button("재시도") {
                    Task { await store.retryStartingRecording() }
                }
                .disabled(!store.isReady || store.isStarting)
                Button("나중에", role: .cancel) { store.clearRecordingError() }
            } else {
                Button("확인", role: .cancel) { store.clearRecordingError() }
            }
        } message: {
            Text(store.errorMessage ?? "녹화 중 문제가 발생했습니다.")
        }
        .alert(
            "데모 안내",
            isPresented: Binding(
                get: { demoControl?.errorMessage != nil },
                set: { if !$0 { demoControl?.clearError() } }
            )
        ) {
            Button("다시 시도") {
                guard let demoControl else { return }
                Task { await demoControl.startTraining() }
            }
            Button("확인", role: .cancel) { demoControl?.clearError() }
        } message: {
            Text(demoControl?.errorMessage ?? "데모 훈련을 시작하지 못했습니다.")
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch store.phase {
        case .join:
            SessionJoinView(
                isJoining: store.isJoining,
                onStartDemo: startDemoAction,
                onJoin: { pin, name in store.join(pin: pin, memberName: name) }
            )
        case .setup:
            setupView
        case .waiting, .recording, .saving, .correcting:
            MemberTrainingFlowView(demoControl: demoControl)
        case .saved:
            RecordingSaveTestView(recordingURLs: store.savedRecordingURLs,
                isDemo: store.isDemoMode,
                raw: store.rawTrack, correction: store.correction, mapImage: floorPlan,
                files: store.recordingFiles, filesSaved: store.filesSaved,
                onHome: { store.returnToJoin() },
                onRetry: { Task { await store.retrySaving() } },
                onDiscardDemo: discardFailedDemo) {
                store.startUploading()
            }
        case .uploading:
            RecordingUploadView(
                isDemo: store.isDemoMode,
                progress: store.uploadProgress,
                isComplete: store.isUploadComplete,
                isAbandoned: store.isUploadAbandoned,
                statusMessage: store.uploadStatusMessage,
                errorMessage: store.uploadErrorMessage,
                isUploading: store.isUploading || store.isFinalizingUploadFailure,
                onRetry: { await store.retryUploading() },
                onAbandon: { await store.abandonUploading() },
                onHome: finishDemoOrReturnHome
            )
            .task { await store.uploadRecording() }
        }
    }

    @ViewBuilder
    private var setupView: some View {
        if let floorPlan {
            StartPositionSetupView(
                floorPlan: floorPlan,
                startPoint: store.startPoint,
                directionPoint: store.directionPoint,
                onBack: {
                    if demoMode.isActive {
                        demoMode.stop()
                    } else {
                        store.returnToJoin()
                    }
                }
            ) { start, direction in
                store.confirmPosition(start: start, direction: direction)
            }
        } else {
            ContentUnavailableView("도면을 불러올 수 없습니다", systemImage: "map")
        }
    }

    private var startDemoAction: (() -> Void)? {
        guard !demoMode.isActive else { return nil }
        return { demoMode.start() }
    }

    private func finishDemoOrReturnHome() {
        if store.isDemoMode {
            if store.finishDemo() { demoMode.stop() }
        } else {
            store.returnToJoin()
        }
    }

    private func discardFailedDemo() {
        guard store.discardFailedDemo() else { return }
        demoMode.stop()
    }

    private var canExitDemo: Bool {
        switch store.phase {
        case .join, .setup, .waiting:
            true
        case .recording, .saving, .correcting, .saved, .uploading:
            false
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 12) {
            Label("데모 모드 · 서버에 저장되지 않음", systemImage: "testtube.2")
                .dsTextStyle(DSTypography.captionMedium14)

            Spacer(minLength: 8)

            Button("데모 종료", action: demoMode.stop)
                .dsTextStyle(DSTypography.captionMedium14)
                .disabled(!canExitDemo)
                .accessibilityHint(canExitDemo ? "실제 PIN 참가 화면으로 돌아갑니다." : "기록 처리를 완료한 뒤 종료할 수 있습니다.")
                .accessibilityIdentifier("demo.exit")
        }
        .foregroundStyle(DSColor.contentPrimary)
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
        .background(DSColor.surfacePrimary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DSColor.borderPrimary).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("demo.banner")
    }
}
