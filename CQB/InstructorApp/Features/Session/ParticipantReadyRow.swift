import CQBDesignSystem
import SwiftUI

struct ParticipantReadyRow: View {
    let participant: InstructorParticipant

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: DSSpacing.s40) {
                Text(formattedNumber)
                Text(participant.name)
            }
            .dsTextStyle(DSTypography.headingSemiBold20)
            .foregroundStyle(DSColor.contentPrimary)

            Spacer()

            HStack(spacing: participant.isReady ? 27 : 39) {
                Text(participant.isReady ? "준비완료" : "준비 중")
                    .dsTextStyle(DSTypography.bodyRegular20)

                Image(systemName: participant.isReady ? "checkmark.circle.fill" : "circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(participant.isReady ? DSColor.contentPrimary : DSColor.contentDisabled)
            .frame(width: 124, alignment: .leading)
        }
        .padding(DSSpacing.s20)
        .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70)
        .background(DSColor.surfacePrimary)
        .clipShape(.rect(cornerRadius: DSRadius.large))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(formattedNumber), \(participant.name)")
        .accessibilityValue(participant.isReady ? "준비 완료" : "준비 중")
    }

    private var formattedNumber: String {
        participant.number.formatted(.number.precision(.integerLength(2)))
    }
}

#Preview("대원 준비 상태") {
    VStack(spacing: DSSpacing.s12) {
        ParticipantReadyRow(
            participant: InstructorParticipant(
                id: "ready",
                number: 1,
                name: "강유키",
                isReady: true,
                x: 0,
                y: 0
            )
        )
        ParticipantReadyRow(
            participant: InstructorParticipant(
                id: "setting",
                number: 2,
                name: "매버릭",
                isReady: false,
                x: 0,
                y: 0
            )
        )
    }
    .padding(DSSpacing.s40)
    .frame(width: 886)
    .background(DSColor.backgroundElevated)
    .preferredColorScheme(.dark)
}
