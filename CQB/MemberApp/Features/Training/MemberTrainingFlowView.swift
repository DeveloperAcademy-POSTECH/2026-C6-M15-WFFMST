import CQBDesignSystem
import SwiftUI

/// 대기·기록 화면과 실행 환경별 보조 컨트롤을 조립한다.
struct MemberTrainingFlowView: View {
    @Environment(MemberStore.self) private var store
    var demoControl: MemberDemoSessionControl?

    var body: some View {
        TrainingRecordingView(
            phase: store.phase,
            startedAt: store.recordingStartedAt,
            onFinish: { Task { await store.finishRecording() } },
            onReset: { store.resetPosition() },
            allowsPositionReset: store.canResetPosition,
            allowsManualStop: true,
            canRetryRecordingStart: store.canRetryRecordingStart,
            isStartingRecording: store.isStarting,
            uploadStatusMessage: store.uploadStatusMessage,
            onRetryRecordingStart: { Task { await store.retryStartingRecording() } },
            onCameraReadinessChange: { store.updateTrackingReadiness($0) },
            cameraService: store.cameraService,
            onStopRecording: { await store.finishRecording() }
        )
        .overlay(alignment: .bottom) {
            if demoControl != nil, store.phase == .waiting {
                Button(demoStartTitle ?? "데모 훈련 시작", action: startDemoTraining)
                    .font(DSTypography.body.weight(.semibold))
                    .foregroundStyle(DSColor.background)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
                    .background(DSColor.main, in: RoundedRectangle(cornerRadius: 4))
                    .disabled(!store.isReady || isDemoStartDisabled)
                    .opacity(store.isReady && !isDemoStartDisabled ? 1 : 0.55)
                    .accessibilityHint(store.isReady
                        ? "별도 iPad 없이 로컬 데모 훈련을 시작합니다."
                        : "카메라와 AR 추적 준비가 끝나면 사용할 수 있습니다.")
                    .accessibilityIdentifier("demo.startTraining")
                    .padding(.bottom, 24)
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        .safeAreaInset(edge: .bottom) {
            if demoControl == nil, store.phase == .waiting, store.isReadinessTestAvailable {
                Toggle(isOn: Binding(
                    get: { store.isSimulatedReady },
                    set: { store.setSimulatedReadiness($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("준비 완료 전송 (테스트)").font(.headline)
                        Text("에뮬레이터 전용 · 서버 준비 상태만 변경하며 AR·녹화는 지원하지 않습니다.")
                            .font(.caption)
                    }
                }
                .accessibilityIdentifier("emulator-readiness-toggle")
                .disabled(!store.canResetPosition)
                .tint(DSColor.main)
                .foregroundStyle(DSColor.white)
                .padding()
                .background(DSColor.area1)
            }
        }
        #endif
    }

    private var demoStartTitle: String? {
        guard let demoControl else { return nil }
        if demoControl.isStarting { return "데모 훈련 시작 중…" }
        if demoControl.hasStarted || store.isWaitingForTrainingStart {
            return "카메라 준비 후 자동으로 시작합니다"
        }
        return "데모 훈련 시작"
    }

    private var isDemoStartDisabled: Bool {
        (demoControl?.isStarting ?? false) || (demoControl?.hasStarted ?? false)
    }

    private func startDemoTraining() {
        guard let demoControl else { return }
        Task { await demoControl.startTraining() }
    }
}
