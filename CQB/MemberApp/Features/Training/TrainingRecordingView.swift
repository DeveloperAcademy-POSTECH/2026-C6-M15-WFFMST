import CQBDesignSystem
import SwiftUI

/// 실제 카메라 수명주기를 소유하고 표시 상태를 순수 화면에 전달한다.
struct TrainingRecordingView: View {
    let phase: MemberPhase
    let startedAt: Date?
    let onFinish: () -> Void
    var onReset: (() -> Void)? = nil
    var allowsPositionReset = false
    var allowsManualStop = false
    var canRetryRecordingStart = false
    var isStartingRecording = false
    var uploadStatusMessage = "영상 조각 업로드 준비 중"
    var onRetryRecordingStart: () -> Void = {}
    var onCameraReadinessChange: (Bool) -> Void = { _ in }
    var cameraService = ARRecordingService()
    var onStopRecording: () async -> Void = {}
    @State private var isCameraReady = false

    var body: some View {
        ZStack {
            CameraPreviewView(
                service: cameraService,
                isRecording: phase == .recording,
                isWaiting: phase == .waiting,
                onStopRecording: onStopRecording,
                onAvailabilityChange: {
                    isCameraReady = $0
                    onCameraReadinessChange($0)
                }
            )
            TrainingRecordingContent(
                phase: phase, startedAt: startedAt, onFinish: onFinish,
                onReset: onReset, allowsPositionReset: allowsPositionReset,
                allowsManualStop: allowsManualStop, canRetryRecordingStart: canRetryRecordingStart,
                isStartingRecording: isStartingRecording, uploadStatusMessage: uploadStatusMessage,
                onRetryRecordingStart: onRetryRecordingStart,
                isCameraReady: isCameraReady, cameraStatusMessage: cameraService.statusMessage,
                cameraError: cameraService.fatalError,
                trackingWarning: cameraService.trackingWarning, audioWarning: cameraService.audioWarning,
                onPrepareCamera: { Task { await cameraService.start() } }
            )
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
    }
}

/// 카메라를 실행하지 않고 동일한 상태 UI를 Preview에서 재현한다.
private struct TrainingRecordingContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let phase: MemberPhase
    let startedAt: Date?
    let onFinish: () -> Void
    var onReset: (() -> Void)? = nil
    var allowsPositionReset = false
    var allowsManualStop = false
    var canRetryRecordingStart = false
    var isStartingRecording = false
    var uploadStatusMessage = "영상 조각 업로드 준비 중"
    var onRetryRecordingStart: () -> Void = {}
    var isCameraReady = false
    var cameraStatusMessage = "카메라 준비 중"
    var cameraError: String? = nil
    var trackingWarning: String? = nil
    var audioWarning: String? = nil
    var onPrepareCamera: () -> Void = {}
    @State private var isShowingManualStopConfirmation = false

    private var isWaiting: Bool { phase == .waiting }

    private var title: String {
        switch phase {
        case .waiting: isCameraReady ? "준비 완료" : "추적 준비 중"
        case .saving: "영상·동선 저장 중"
        case .correcting: "동선 보정 중"
        default: "영상 및 동선 수집 중"
        }
    }

    private var guidanceMessage: String? {
        if let error = cameraError { return error }
        if phase == .recording {
            let warnings = [trackingWarning, audioWarning].compactMap { $0 }
            return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        }
        if isWaiting {
            // isReady는 AR 추적 준비 상태이며, WorldMap 스캔·재위치 인식 완료를 뜻하지 않는다.
            return isCameraReady
                ? "카메라와 동선 추적 준비가 완료됐습니다.\n중앙에서 통제하기 전까지 방탄 캐리어에 가로로 넣고 대기해주세요."
                : cameraStatusMessage
        }
        return phase == .correcting ? "동선을 보정하고 있습니다." : "녹화 파일을 저장하고 있습니다."
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: DSSpacing.s20) {
                    ScrollView {
                        if isWaiting && !dynamicTypeSize.isAccessibilitySize {
                            ZStack(alignment: .topLeading) {
                                header
                                guidance
                                    .frame(maxWidth: 562)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, DSSpacing.s60 * 2 - DSSpacing.s4)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: DSSpacing.s20) {
                                header
                                guidance.frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    HStack {
                        Spacer(minLength: 0)
                        controls.frame(maxWidth: 362)
                    }
                }
                .padding(.horizontal, DSSpacing.s40)
                .padding(.top, DSSpacing.s40)
                .padding(.bottom, max(0, DSSpacing.s60 - geometry.safeAreaInsets.bottom))
            }
            .ignoresSafeArea(.container, edges: .horizontal)
            .foregroundStyle(DSColor.contentPrimary)
            .confirmationDialog("종료 신호를 받지 못했나요?", isPresented: $isShowingManualStopConfirmation) {
                Button("훈련 직접 종료", role: .destructive, action: onFinish)
                Button("취소", role: .cancel) {}
            } message: {
                Text("교관의 종료 신호를 받을 수 없을 때만 사용해주세요.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DSSpacing.s20) {
            VStack(alignment: .leading, spacing: DSSpacing.s4) {
                Text(title)
                    .dsTextStyle(DSTypography.headingBold20)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if phase == .recording {
                    Text("네트워크가 끊겨도 기기에 계속 저장")
                        .dsTextStyle(DSTypography.bodyRegular20)
                    Text(uploadStatusMessage)
                        .dsTextStyle(DSTypography.bodyRegular12)
                        .foregroundStyle(DSColor.contentSecondary)
                }
            }
            Spacer(minLength: DSSpacing.s12)
            if phase == .recording, let startedAt { recordingTimer(startedAt: startedAt) }
        }
        .foregroundStyle(phase == .recording ? DSPalette.Neutral.white : DSColor.contentPrimary)
    }

    @ViewBuilder
    private var guidance: some View {
        if let guidanceMessage {
            MemberGuidanceView(message: guidanceMessage, presentation: .camera)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if isWaiting {
            VStack(spacing: DSSpacing.s12) {
                if cameraError != nil {
                    Button("카메라 다시 준비", action: onPrepareCamera)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.dsSecondary)
                }
                if canRetryRecordingStart {
                    ActionButton(isStartingRecording ? "녹화 준비 중…" : "녹화 재시도", action: onRetryRecordingStart)
                        .disabled(!isCameraReady || isStartingRecording)
                } else if allowsPositionReset, !isCameraReady, let onReset {
                    ActionButton("설정하기", action: onReset)
                        .accessibilityLabel("출발 위치 다시 설정하기")
                }
            }
        } else if allowsManualStop && phase == .recording {
            Button("직접 종료") { isShowingManualStopConfirmation = true }
                .dsTextStyle(DSTypography.captionMedium14)
                .padding(DSSpacing.s12)
                .background(DSColor.surfacePrimary, in: Capsule())
        }
    }

    private func recordingTimer(startedAt: Date) -> some View {
        HStack(spacing: DSSpacing.s16) {
            Circle()
                .fill(DSPalette.Red.r400)
                .frame(width: DSSpacing.s12, height: DSSpacing.s12)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .dsTextStyle(DSTypography.bodyRegular20)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, DSSpacing.s12)
        .frame(minWidth: 105, minHeight: 30)
        .background(DSColor.surfacePrimary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("녹화 경과 시간")
    }
}

#Preview("03 추적 준비 중", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .waiting, startedAt: nil, onFinish: {},
        onReset: { print("Preview 위치 재설정") }, allowsPositionReset: true,
        cameraStatusMessage: "카메라를 천천히 움직여 주변 공간을 확인해주세요."
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("03 준비 완료", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .waiting, startedAt: nil, onFinish: {},
        onReset: { print("Preview 위치 재설정") }, allowsPositionReset: true,
        isCameraReady: true
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("03 카메라 권한 거부", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .waiting, startedAt: nil, onFinish: {},
        onReset: { print("Preview 위치 재설정") }, allowsPositionReset: true,
        cameraStatusMessage: "설정에서 카메라 접근을 허용해주세요."
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("03 카메라 오류 · 재준비", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .waiting, startedAt: nil, onFinish: {},
        onReset: { print("Preview 위치 재설정") }, allowsPositionReset: true,
        cameraError: "카메라 연결이 중단됐습니다. 카메라를 다시 준비해주세요.",
        onPrepareCamera: { print("Preview 카메라 재준비") }
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("03 녹화 재시도 · 가능", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .waiting, startedAt: nil, onFinish: {},
        canRetryRecordingStart: true,
        onRetryRecordingStart: { print("Preview 녹화 재시도") }, isCameraReady: true
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("03 녹화 재시도 · 준비 전", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .waiting, startedAt: nil, onFinish: {},
        canRetryRecordingStart: true,
        onRetryRecordingStart: { print("Preview 비활성 상태에서 호출되면 안 됨") }
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("03 녹화 재시도 · 진행 중", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .waiting, startedAt: nil, onFinish: {},
        canRetryRecordingStart: true, isStartingRecording: true,
        onRetryRecordingStart: { print("Preview 중복 재시도 방지") }, isCameraReady: true
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("03 준비 완료 · 큰 글자", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .waiting, startedAt: nil, onFinish: {},
        onReset: { print("Preview 위치 재설정") }, allowsPositionReset: true,
        isCameraReady: true
    )
    .dynamicTypeSize(.accessibility3)
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("03 준비 완료 · 작은 화면", traits: .fixedLayout(width: 667, height: 375)) {
    TrainingRecordingContent(
        phase: .waiting, startedAt: nil, onFinish: {},
        onReset: { print("Preview 위치 재설정") }, allowsPositionReset: true,
        isCameraReady: true
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("04 기록 중 · 직접 종료", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .recording, startedAt: Date().addingTimeInterval(-12),
        onFinish: { print("Preview 직접 종료 확인") }, allowsManualStop: true,
        uploadStatusMessage: "영상 조각 전송 중 · 3/5", isCameraReady: true
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("04 기록 중 · 추적 및 오디오 경고", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .recording, startedAt: Date().addingTimeInterval(-72),
        onFinish: { print("Preview 직접 종료 확인") }, allowsManualStop: true,
        uploadStatusMessage: "네트워크 연결 대기 · 기기에 저장 중", isCameraReady: true,
        trackingWarning: "주변 특징이 부족합니다. 카메라가 가려지지 않았는지 확인해주세요.",
        audioWarning: "마이크를 사용할 수 없어 영상만 기록하고 있습니다."
    )
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("04 기록 중 · 큰 글자", traits: .landscapeLeft) {
    TrainingRecordingContent(
        phase: .recording, startedAt: Date().addingTimeInterval(-72),
        onFinish: { print("Preview 직접 종료 확인") }, allowsManualStop: true,
        isCameraReady: true, trackingWarning: "카메라가 가려지지 않았는지 확인해주세요."
    )
    .dynamicTypeSize(.accessibility3)
    .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("04 저장 중", traits: .landscapeLeft) {
    TrainingRecordingContent(phase: .saving, startedAt: nil, onFinish: {})
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
}

#Preview("04 보정 중", traits: .landscapeLeft) {
    TrainingRecordingContent(phase: .correcting, startedAt: nil, onFinish: {})
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
}
