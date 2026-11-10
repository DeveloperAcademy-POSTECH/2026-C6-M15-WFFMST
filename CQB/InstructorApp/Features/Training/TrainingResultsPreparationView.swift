import CQBCore
import CQBDesignSystem
import SwiftUI

struct TrainingResultsPreparationView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        TrainingStatusLayout(elapsed: store.trainingElapsed(at: .now)) {
            Button {} label: {
                Text("AAR 준비 중…")
                    .dsTextStyle(DSTypography.headingBold20)
                    .frame(width: 180, height: 55)
            }
            .buttonStyle(TrainingFinishButtonStyle())
            .disabled(true)
            .accessibilityIdentifier("results.preparingAction")
        } statusContent: {
            resultsPreparationStatus
        }
        .accessibilityIdentifier("results.preparation")
    }

    @ViewBuilder
    private var resultsPreparationStatus: some View {
        if store.trainingRecords.connectionState == .failed,
           let error = store.trainingRecords.errorMessage {
            HStack(spacing: DSSpacing.s16) {
                Text(error)
                    .dsTextStyle(DSTypography.bodyRegular16)

                Button("다시 연결", action: store.retryRecordingObservation)
                    .buttonStyle(.dsSecondary)
                    .disabled(!store.trainingRecords.canRetry)
                    .accessibilityIdentifier("results.reconnect")
            }
            .foregroundStyle(DSColor.contentSecondary)
        } else {
            ProgressView("AAR 준비 중…")
                .tint(DSColor.contentPrimary)
                .foregroundStyle(DSColor.contentSecondary)
                .accessibilityIdentifier("results.preparing")
        }
    }
}

#Preview("AAR 준비 중") {
    let session = Session(
        id: UUID(),
        pin: "123456",
        name: "시가전 훈련",
        status: .ended,
        startedAt: .now.addingTimeInterval(-432),
        floorPlan: InstructorFloorPlan(
            id: "floor-plan",
            name: "훈련장",
            fileName: "floor-plan.png",
            referenceDistance: 10
        ).reference
    )

    TrainingResultsPreparationView()
        .environment(InstructorStore(previewSession: session, previewPhase: .resultsPreparation))
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
