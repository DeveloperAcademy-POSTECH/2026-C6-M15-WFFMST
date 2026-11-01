import CQBDesignSystem
import SwiftUI

struct TrainingResultsPreparationView: View {
    @Environment(InstructorStore.self) private var store
    @State private var participantPendingExclusion: ParticipantRecordingProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("훈련 결과 준비")
                    .font(DSTypography.h1)
                Spacer()
                Text("처리 종료 \(store.trainingRecords.terminalCount)/\(store.trainingParticipants.count) · 제외 \(store.trainingRecords.excludedCount)")
                    .font(DSTypography.h3)
                    .monospacedDigit()
                    .accessibilityIdentifier("results.summary")
            }

            Text("기록이 완료 또는 실패로 확정되면 AAR로 이동합니다. 처리가 멈춘 대원은 제외하고 완료된 대원의 자료로 진행할 수 있습니다.")
                .font(DSTypography.bodySmall)
                .foregroundStyle(InstructorColor.textSecondary)

            if store.trainingRecords.connectionState == .connecting {
                ProgressView("기록 상태 연결 중…")
                    .accessibilityIdentifier("results.connecting")
            } else if let error = store.trainingRecords.errorMessage {
                HStack {
                    Text(error)
                    Spacer()
                    Button("다시 연결", action: store.retryRecordingObservation)
                        .disabled(!store.trainingRecords.canRetry)
                        .accessibilityIdentifier("results.reconnect")
                }
                .foregroundStyle(InstructorColor.textSecondary)
            }

            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(store.trainingRecords.rows) { row in
                        HStack {
                            Text(row.participant.name)
                            Spacer()
                            if store.trainingRecords.excludedParticipantIDs.contains(row.id) {
                                Text("AAR 제외")
                            } else {
                                Text(row.state.title)
                            }
                            if store.trainingRecords.canExcludeParticipant(row.id) {
                                Button("AAR에서 제외") { participantPendingExclusion = row }
                                    .accessibilityIdentifier("results.member.\(row.id).exclude")
                            }
                        }
                        .font(DSTypography.h3)
                        .padding(20)
                        .background(InstructorColor.surfaceRaised)
                        .clipShape(.rect(cornerRadius: 4))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("results.member.\(row.id)")
                    }
                }
            }

            HStack {
                if store.trainingRecords.excludedCount > 0,
                   store.trainingRecords.aarEligibleParticipantIDs.isEmpty {
                    Text("완료된 기록이 없어 AAR을 시작할 수 없습니다.")
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(InstructorColor.textSecondary)
                        .accessibilityIdentifier("results.noAvailableRecords")
                }
                Spacer()
                Button("완료된 대원으로 AAR 시작", action: store.proceedToAAR)
                    .disabled(!store.trainingRecords.canProceedToAAR)
                    .accessibilityIdentifier("results.proceedAAR")
                Button("홈으로", action: store.returnHome)
                    .accessibilityIdentifier("results.home")
            }
        }
        .padding(48)
        .foregroundStyle(InstructorColor.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
}
