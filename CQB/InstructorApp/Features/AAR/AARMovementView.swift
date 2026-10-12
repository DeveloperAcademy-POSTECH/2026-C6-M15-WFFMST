import CQBDesignSystem
import SwiftUI

struct AARMovementView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(InstructorColor.surfaceBase)

                floorPlan

                ForEach(store.selectedParticipants) { participant in
                    participantMarker(participant)
                        .position(
                            x: geometry.size.width * participant.x,
                            y: geometry.size.height * participant.y
                        )
                }
            }
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
            }
        }
        .accessibilityIdentifier("aar.movement")
    }

    @ViewBuilder
    private var floorPlan: some View {
        if let image = store.selectedPlanImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .opacity(0.5)
                .padding(20)
                .accessibilityLabel("선택한 훈련 도면")
        } else {
            ContentUnavailableView(
                "도면 미리보기 없음",
                systemImage: "map",
                description: Text("선택한 훈련 도면을 불러오지 못했습니다.")
            )
            .foregroundStyle(InstructorColor.textSecondary)
        }
    }

    private func participantMarker(_ participant: InstructorParticipant) -> some View {
        Text("\(participant.number)")
            .font(markerFont)
            .foregroundStyle(InstructorColor.textPrimary)
            .monospacedDigit()
            .frame(width: 49, height: 49)
            .background(InstructorColor.teamOne, in: Circle())
            .accessibilityLabel("\(participant.displayName) 위치")
    }

    private var markerFont: Font {
        DSFonts.register()
        return .custom("NotoSansKR-Bold", size: 14, relativeTo: .body)
    }
}

#Preview("AAR 동선") {
    let store = InstructorPreviewFixture.store(floorPlan: DemoFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    ), phase: .aar)

    return AARMovementView()
        .environment(store)
        .frame(width: 1_008, height: 896)
        .preferredColorScheme(.dark)
}
