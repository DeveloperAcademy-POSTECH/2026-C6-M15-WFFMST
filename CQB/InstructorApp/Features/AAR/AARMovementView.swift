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
                    ForEach(store.aarParticipants) { participant in
                        if let position = aarStore.position(for: participant.id) {
                            Button {
                                store.toggleParticipantSelection(participant.id)
                            } label: {
                                participantMarker(participant)
                            }
                            .buttonStyle(.plain)
                                .opacity(position.presence == .tracked ? 1 : 0.35)
                                .position(layout.viewPoint(for: position.point))
                            .accessibilityLabel(markerAccessibilityLabel(participant))
                            .accessibilityHint(store.isParticipantSelected(participant.id)
                                ? "선택을 해제합니다"
                                : "영상 패널에 추가합니다")
                            .accessibilityIdentifier("aar.marker.\(participant.id)")
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
        let slotNumber = store.videoSlotNumber(for: participant.id)

        return ZStack {
            Circle()
                .fill(slotNumber == nil ? InstructorColor.playerSurface : InstructorColor.actionPrimary)
                .frame(width: slotNumber == nil ? 18 : 48, height: slotNumber == nil ? 18 : 48)
                .overlay {
                    Circle()
                        .strokeBorder(InstructorColor.textPrimary, lineWidth: slotNumber == nil ? 2 : 0)
                }

            if let slotNumber {
                Text("\(slotNumber)")
                    .font(markerFont)
                    .foregroundStyle(InstructorColor.playerSurface)
                    .monospacedDigit()
            }
        }
        .frame(width: 48, height: 48)
        .contentShape(.circle)
    }

    private func markerAccessibilityLabel(_ participant: InstructorParticipant) -> String {
        if let slotNumber = store.videoSlotNumber(for: participant.id) {
            return "\(participant.name), 선택됨, 영상 \(slotNumber)번"
        }
        return "\(participant.name), 선택되지 않음"
    }

    private var markerFont: Font {
        DSFonts.register()
        return .custom("NotoSansKR-Bold", size: 14, relativeTo: .body)
    }
}

#Preview("AAR 동선") {
    let store = InstructorPreviewFixture.store(floorPlan: InstructorFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    ), phase: .aar)

    return AARMovementView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_008, height: 896)
        .preferredColorScheme(.dark)
}
