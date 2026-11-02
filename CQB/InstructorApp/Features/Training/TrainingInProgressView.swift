import CQBDesignSystem
import SwiftUI

struct TrainingInProgressView: View {
    @Environment(InstructorStore.self) private var store
    @State private var isShowingFinishConfirmation = false
    @State private var participantPendingExclusion: ParticipantRecordingProgress?

    var body: some View {
        ZStack {
            DSColor.backgroundPrimary
                .ignoresSafeArea()

            if store.phase == .resultsPreparation {
                VStack(spacing: 0) {
                    header
                    resultsPreparationContent
                        .padding(.top, DSSpacing.s32)
                }
                .padding(DSSpacing.s40)
            } else {
                trainingTimer

                VStack(spacing: 0) {
                    header
                    Spacer()
                    trainingStatusContent
                }
                .padding(DSSpacing.s40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("훈련을 종료하시겠습니까?", isPresented: $isShowingFinishConfirmation) {
            Button("확인", action: store.finishTraining)
            Button("취소", role: .cancel) {}
        } message: {
            Text("훈련이 종료되면 AAR 화면으로 넘어갑니다.")
        }
        .alert("이 대원을 AAR에서 제외할까요?", isPresented: Binding(
            get: { participantPendingExclusion != nil },
            set: { if !$0 { participantPendingExclusion = nil } }
        ), presenting: participantPendingExclusion) { row in
            Button("제외", role: .destructive) {
                store.excludeParticipantFromAAR(row.id)
                participantPendingExclusion = nil
            }
            Button("취소", role: .cancel) { participantPendingExclusion = nil }
        } message: { row in
            Text("\(row.participant.name)의 영상과 동선은 이번 AAR에 포함되지 않습니다.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(store.phase == .resultsPreparation ? "훈련 결과 준비" : "훈련 기록 중")
                .dsTextStyle(DSTypography.headingBold36)
                .foregroundStyle(DSColor.contentPrimary)

            Spacer()

            if store.phase == .trainingInProgress {
                Button {
                    isShowingFinishConfirmation = true
                } label: {
                    Text(finishButtonTitle)
                        .dsTextStyle(DSTypography.headingBold20)
                        .frame(width: 180, height: 55)
                }
                .buttonStyle(TrainingFinishButtonStyle())
                .disabled(!store.canFinishTraining)
                .accessibilityIdentifier("training.finish")
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var trainingTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = store.trainingElapsed(at: context.date)
            HStack(spacing: DSSpacing.s32) {
                Circle()
                    .fill(InstructorColor.trainingRecordingIndicator)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                Text(elapsed ?? "--:--")
                    .dsTextStyle(DSTypography.headingBold36)
                    .foregroundStyle(DSColor.contentPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(elapsed.map { "훈련 경과 시간 \($0)" } ?? "서버 시작 시각 확인 중")
            .accessibilityIdentifier("training.elapsed")
        }
    }

    private var trainingStatusContent: some View {
        VStack(spacing: DSSpacing.s16) {
            if let error = store.trainingActionError {
                Text(error)
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(DSColor.statusError)
                    .accessibilityIdentifier("training.finishError")
            }

            if store.sessionConnectionState == .connecting {
                ProgressView("서버 훈련 정보 연결 중…")
                    .tint(DSColor.contentPrimary)
                    .foregroundStyle(DSColor.contentSecondary)
            } else if let error = store.sessionObservationError {
                HStack(spacing: DSSpacing.s16) {
                    Text(error)
                        .dsTextStyle(DSTypography.bodyRegular16)

                    Button("다시 연결", action: store.retrySessionObservation)
                        .buttonStyle(.dsSecondary)
                        .disabled(!store.canRetrySessionObservation)
                        .accessibilityIdentifier("training.reconnect")
                }
                .foregroundStyle(DSColor.contentSecondary)
            }
        }
    }

    private var resultsPreparationContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s24) {
            HStack {
                Text("대원별 기록 상태")
                    .dsTextStyle(DSTypography.headingSemiBold24)
                    .foregroundStyle(DSColor.contentPrimary)

                Spacer()

                Text(
                    "처리 종료 \(store.trainingRecords.terminalCount)/\(store.trainingParticipants.count)"
                        + " · 제외 \(store.trainingRecords.excludedCount)"
                )
                .dsTextStyle(DSTypography.bodyRegular16)
                .foregroundStyle(DSColor.contentSecondary)
                .monospacedDigit()
                .accessibilityIdentifier("results.summary")
            }

            Text("기록이 완료 또는 실패로 확정되면 AAR로 자동 이동합니다. 처리가 멈춘 대원은 제외하고 완료된 대원의 자료로 진행할 수 있습니다.")
                .dsTextStyle(DSTypography.bodyRegular16)
                .foregroundStyle(DSColor.contentSecondary)
            recordingConnectionStatus

            ScrollView {
                LazyVStack(spacing: DSSpacing.s12) {
                    ForEach(store.trainingRecords.rows) { row in
                        recordingRow(row)
                    }
                }
            }

            HStack(spacing: DSSpacing.s16) {
                if store.trainingRecords.excludedCount > 0,
                   store.trainingRecords.aarEligibleParticipantIDs.isEmpty {
                    Text("완료된 기록이 없어 AAR을 시작할 수 없습니다.")
                        .dsTextStyle(DSTypography.bodyRegular16)
                        .foregroundStyle(DSColor.contentSecondary)
                        .accessibilityIdentifier("results.noAvailableRecords")
                }

                Spacer()

                Button("홈으로", action: store.returnHome)
                    .buttonStyle(.dsSecondary)
                    .accessibilityIdentifier("results.home")

                Button("완료된 대원으로 AAR 시작", action: store.proceedToAAR)
                    .buttonStyle(.dsPrimary)
                    .disabled(!store.trainingRecords.canProceedToAAR)
                    .accessibilityIdentifier("results.proceedAAR")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var recordingConnectionStatus: some View {
        if store.trainingRecords.connectionState == .connecting {
            ProgressView("기록 상태 연결 중…")
                .tint(DSColor.contentPrimary)
                .foregroundStyle(DSColor.contentSecondary)
                .accessibilityIdentifier("results.connecting")
        } else if let error = store.trainingRecords.errorMessage {
            HStack(spacing: DSSpacing.s16) {
                Text(error)
                    .dsTextStyle(DSTypography.bodyRegular16)

                Button("다시 연결", action: store.retryRecordingObservation)
                    .buttonStyle(.dsSecondary)
                    .disabled(!store.trainingRecords.canRetry)
                    .accessibilityIdentifier("results.reconnect")
            }
            .foregroundStyle(DSColor.contentSecondary)
        }
    }

    private func recordingRow(_ row: ParticipantRecordingProgress) -> some View {
        HStack(spacing: DSSpacing.s16) {
            Text(row.participant.name)
                .dsTextStyle(DSTypography.headingSemiBold20)
                .foregroundStyle(DSColor.contentPrimary)

            Spacer()

            Text(store.trainingRecords.excludedParticipantIDs.contains(row.id)
                ? "AAR 제외"
                : row.state.title)
                .dsTextStyle(DSTypography.bodyRegular16)
                .foregroundStyle(DSColor.contentSecondary)

            if store.trainingRecords.canExcludeParticipant(row.id) {
                Button("AAR에서 제외") { participantPendingExclusion = row }
                    .buttonStyle(.dsSecondary)
                    .accessibilityIdentifier("results.member.\(row.id).exclude")
            }
        }
        .padding(DSSpacing.s20)
        .background(DSColor.backgroundElevated)
        .clipShape(.rect(cornerRadius: DSRadius.small))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("results.member.\(row.id)")
    }

    private var finishButtonTitle: String {
        store.isFinishingTraining ? "훈련 종료 중…" : "훈련 종료"
    }
}

private struct TrainingFinishButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? DSColor.contentInverse : DSColor.contentDisabled)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .contentShape(Capsule())
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return DSColor.actionPrimaryDisabled }
        return isPressed ? DSColor.actionPrimaryPressed : DSColor.actionPrimary
    }
}

#Preview("훈련 중") {
    TrainingInProgressView()
        .environment(InstructorStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
