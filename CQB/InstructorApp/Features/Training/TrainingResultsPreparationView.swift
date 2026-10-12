import CQBDesignSystem
import SwiftUI

struct TrainingResultsPreparationView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("훈련 결과 준비")
                    .font(DSTypography.h1)
                Spacer()
                Text("처리 종료 \(store.trainingRecords.terminalCount)/\(store.trainingParticipants.count)")
                    .font(DSTypography.h3)
                    .monospacedDigit()
                    .accessibilityIdentifier("results.summary")
            }

            Text("참가 대원 전원의 기록이 완료 또는 실패로 확정되면 AAR로 이동합니다. 대원 앱에서 업로드를 시작했는지 확인해주세요.")
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
                            Text(row.state.title)
                        }
                        .font(DSTypography.h3)
                        .padding(20)
                        .background(InstructorColor.surfaceRaised)
                        .clipShape(.rect(cornerRadius: 4))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("results.member.\(row.id)")
                    }
                }
            }

            HStack {
                Spacer()
                Button("홈으로", action: store.returnHome)
                    .accessibilityIdentifier("results.home")
            }
        }
        .padding(48)
        .foregroundStyle(InstructorColor.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
