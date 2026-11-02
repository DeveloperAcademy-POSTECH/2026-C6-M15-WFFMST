import CQBDesignSystem
import SwiftUI

/// iPhone 03(대기) · 04(기록). 가로 카메라 화면 위에 실제 준비·기록 상태를 표시한다.
struct TrainingRecordingView: View {
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
    var onCameraReadinessChange: (Bool) -> Void = { _ in }
    var cameraService = ARRecordingService()
    var onStopRecording: () async -> Void = {}
    @State private var isCameraReady = false
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
        if let error = cameraService.fatalError { return error }
        if phase == .recording {
            let warnings = [cameraService.trackingWarning, cameraService.audioWarning].compactMap { $0 }
            return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        }
        if isWaiting {
            // isReady는 AR 추적 준비 상태이며, WorldMap 스캔·재위치 인식 완료를 뜻하지 않는다.
            return isCameraReady
                ? "카메라와 동선 추적 준비가 완료됐습니다.\n중앙에서 통제하기 전까지 방탄 캐리어에 가로로 넣고 대기해주세요."
                : cameraService.statusMessage
        }
        return phase == .correcting ? "동선을 보정하고 있습니다." : "녹화 파일을 저장하고 있습니다."
    }

    var body: some View {
        ZStack {
            CameraPreviewView(
                service: cameraService,
                isRecording: phase == .recording,
                isWaiting: isWaiting,
                onStopRecording: onStopRecording,
                onAvailabilityChange: {
                    isCameraReady = $0
                    onCameraReadinessChange($0)
                }
            )

            VStack(spacing: DSSpacing.s20) {
                ScrollView {
                    if isWaiting && !dynamicTypeSize.isAccessibilitySize {
                        ZStack(alignment: .topLeading) {
                            header
                            guidance
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, DSSpacing.s60 * 2)
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
            .padding(DSSpacing.s20)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .foregroundStyle(DSColor.contentPrimary)
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
        .confirmationDialog("종료 신호를 받지 못했나요?", isPresented: $isShowingManualStopConfirmation) {
            Button("훈련 직접 종료", role: .destructive, action: onFinish)
            Button("취소", role: .cancel) {}
        } message: {
            Text("교관의 종료 신호를 받을 수 없을 때만 사용해주세요.")
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
                        .dsTextStyle(DSTypography.captionRegular14)
                    Text(uploadStatusMessage)
                        .dsTextStyle(DSTypography.bodyRegular12)
                        .foregroundStyle(DSColor.contentSecondary)
                }
            }
            Spacer(minLength: DSSpacing.s12)
            if phase == .recording, let startedAt { recordingTimer(startedAt: startedAt) }
        }
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
                if cameraService.fatalError != nil {
                    Button("카메라 다시 준비") { Task { await cameraService.start() } }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.dsSecondary)
                }
                if canRetryRecordingStart {
                    ActionButton(isStartingRecording ? "녹화 준비 중…" : "녹화 재시도", action: onRetryRecordingStart)
                        .disabled(!isCameraReady || isStartingRecording)
                } else if allowsPositionReset, let onReset {
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
        HStack(spacing: DSSpacing.s12) {
            Circle()
                .fill(DSColor.statusError)
                .frame(width: DSSpacing.s12, height: DSSpacing.s12)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, DSSpacing.s12)
        .padding(.vertical, DSSpacing.s4)
        .background(DSColor.surfacePrimary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("녹화 경과 시간")
    }
}

#Preview("03 시작 대기", traits: .landscapeLeft) {
    TrainingRecordingView(phase: .waiting, startedAt: nil, onFinish: {})
}

#Preview("04 영상·동선 기록", traits: .landscapeLeft) {
    TrainingRecordingView(phase: .recording, startedAt: Date().addingTimeInterval(-12), onFinish: {})
}

#Preview("04 저장·보정", traits: .landscapeLeft) {
    TrainingRecordingView(phase: .correcting, startedAt: nil, onFinish: {})
}
