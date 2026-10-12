import CQBCore
import CQBDesignSystem
import SwiftUI

struct AARMovementView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(AARStore.self) private var aarStore

    // Figma(노드 762:3230 map canvas): 도면은 여백 없이 영역에 비율을 유지해 맞춘다.
    private let floorPlanPadding: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(InstructorColor.surfaceBase)

                floorPlan

                if let imageSize = aarStore.floorPlanImageSize {
                    let layout = AARFloorPlanLayout(
                        imageSize: imageSize,
                        container: geometry.size,
                        padding: floorPlanPadding
                    )
                    ForEach(store.selectedParticipants) { participant in
                        if let position = aarStore.position(for: participant.id) {
                            participantMarker(participant)
                                .opacity(position.presence == .tracked ? 1 : 0.35)
                                .position(layout.viewPoint(for: position.point))
                        }
                    }
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
        if let image = aarStore.floorPlanImage ?? store.selectedPlanImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .opacity(0.5)
                .padding(floorPlanPadding)
                .accessibilityLabel("선택한 훈련 도면")
        } else if aarStore.isLoading {
            ProgressView("도면과 동선을 불러오는 중")
                .foregroundStyle(InstructorColor.textSecondary)
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
    ))
    store.startTraining()
    store.finishTraining()

    return AARMovementView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_008, height: 896)
        .preferredColorScheme(.dark)
}
