import CQBDesignSystem
import SwiftUI

struct ParticipantReadyRow: View {
    let participant: InstructorParticipant

    var body: some View {
        HStack(spacing: 16) {
            Text(participantLabel)
                .font(DSTypography.h3)
                .foregroundStyle(InstructorColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(participant.isReady ? "준비 완료" : "설정중")
                .font(DSTypography.bodySmall)
                .foregroundStyle(participant.isReady ? InstructorColor.actionPrimary : InstructorColor.textSecondary)
                .frame(width: 180, alignment: .trailing)

            if participant.isReady {
                Image("InstructorReadyIcon")
                    .renderingMode(.template)
                    .foregroundStyle(InstructorColor.actionPrimary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
        .background(InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(participant.isReady ? "준비 완료" : "설정 중")
    }

    private var participantLabel: String {
        participant.number.formatted(.number.precision(.integerLength(2))) + " · " + participant.name
    }
}

#Preview("대원 준비 상태") {
    VStack(spacing: 24) {
        ParticipantReadyRow(
            participant: InstructorParticipant(
                id: "ready",
                number: 1,
                name: "강유키1234",
                isReady: true,
                x: 0,
                y: 0
            )
        )
        ParticipantReadyRow(
            participant: InstructorParticipant(
                id: "setting",
                number: 2,
                name: "매버릭1234",
                isReady: false,
                x: 0,
                y: 0
            )
        )
    }
    .padding(48)
    .frame(width: 1_366)
    .background(InstructorColor.canvas)
    .preferredColorScheme(.dark)
}
