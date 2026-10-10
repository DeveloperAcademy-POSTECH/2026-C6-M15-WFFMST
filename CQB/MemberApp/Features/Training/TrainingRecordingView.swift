import SwiftUI
import CQBDesignSystem

/// iPhone 05(대기) · 06(기록). 후면 카메라 미리보기 위에 상태 UI를 표시한다.
struct TrainingRecordingView: View {
    let phase: MemberPhase
    let startedAt: Date?
    let onFinish: () -> Void
    var onStart: (() -> Void)? = nil
    var onReset: (() -> Void)? = nil
    var showsMockControls = true
    var cameraService = ARRecordingService()
    var onStopRecording: () async -> Void = {}
    @State private var isCameraReady = false

    private var isWaiting: Bool { phase == .waiting }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPreviewView(
                    service: cameraService,
                    isRecording: phase == .recording,
                    isWaiting: isWaiting,
                    onStopRecording: onStopRecording,
                    onAvailabilityChange: { isCameraReady = $0 }
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        if isWaiting {
                            Text(isCameraReady ? "준비 완료" : "추적 준비 중")
                                .font(DSTypography.h2)
                        } else if phase == .saving || phase == .correcting {
                            Text(phase == .correcting ? "동선 보정 중" : "영상·동선 저장 중")
                                .font(DSTypography.h2)
                        } else {
                            recordingStatus
                                .frame(maxWidth: 486, alignment: .leading)
                        }
                        Spacer(minLength: 24)
                        if phase == .recording, let startedAt {
                            recordingTimer(startedAt: startedAt)
                        }
                    }
                    Spacer()
                    Text(isWaiting ? "카메라 미리보기" : (phase == .correcting ? "동선을 보정하고 있습니다" : (phase == .saving ? "녹화 파일을 저장하고 있습니다" : "Body cam")))
                        .font(DSTypography.caption)
                }
                .padding(24)

                if isWaiting && isCameraReady {
                    Text("중앙에서 통제하기 전까지 방탄 캐리어에\n가로로 넣고 대기해주세요.")
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
                }

                // Figma에 없는 목업 조작은 별도 메뉴로 구분한다.
                // 실제 신호/카메라 연동 시 showsMockControls를 false로 전달한다.
                if showsMockControls && (isWaiting || phase == .recording) {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Menu {
                                if isWaiting, let onStart {
                                    Button("시작 신호 보내기", action: onStart)
                                        .disabled(!isCameraReady)
                                    if let onReset { Button("위치 다시 지정", action: onReset) }
                                } else if phase == .recording {
                                    Button("훈련 종료", action: onFinish)
                                }
                            } label: {
                                Text("목업 제어")
                                    .font(DSTypography.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(DSColor.area1.opacity(0.94), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .foregroundStyle(DSColor.white)
        }
        .background(DSColor.background.ignoresSafeArea())
    }

    private var recordingStatus: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("영상 녹화 중")
                .font(DSTypography.h3)
                .frame(minHeight: 24)
            Text("영상은 이 iPhone에 저장됩니다.")
                .font(DSTypography.bodySmall)
                .foregroundStyle(DSColor.darkGreen)
                .frame(minHeight: 21)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DSColor.area1, in: RoundedRectangle(cornerRadius: 4))
        .opacity(0.94)
    }

    private func recordingTimer(startedAt: Date) -> some View {
        HStack(spacing: 12) {
            Image("RecordingIndicator")
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(DSTypography.body.weight(.medium))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 112, height: 40)
        .background(DSColor.area1, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel("녹화 경과 시간")
    }
}

#Preview("iPhone 05 · 시작 대기", traits: .landscapeLeft) {
    TrainingRecordingView(phase: .waiting, startedAt: nil, onFinish: {}, showsMockControls: false)
}

#Preview("iPhone 06 · 기록", traits: .landscapeLeft) {
    TrainingRecordingView(phase: .recording, startedAt: Date().addingTimeInterval(-12), onFinish: {}, showsMockControls: false)
}
