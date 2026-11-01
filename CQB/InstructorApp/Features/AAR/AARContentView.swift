import SwiftUI

struct AARContentView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        Group {
            if store.aarScreen == .floorPlan {
                GeometryReader { geometry in
                    let panelWidth = min(360, max(280, geometry.size.width * 0.29))

                    HStack(spacing: 12) {
                        AARMovementView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        AARVideoPanel()
                            .frame(width: panelWidth)
                    }
                }
            } else {
                AARVideoView()
            }
        }
    }
}

private struct AARVideoPanel: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Text("선택 영상")
                        .font(.headline)
                        .foregroundStyle(InstructorColor.textPrimary)

                    Spacer()

                    Button(action: store.openAARVideoScreen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.headline)
                            .foregroundStyle(store.canOpenAARVideoScreen
                                ? InstructorColor.textPrimary
                                : InstructorColor.actionDisabled)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canOpenAARVideoScreen)
                    .accessibilityLabel("영상 화면으로 확대")
                    .accessibilityIdentifier("aar.openVideoScreen")
                }

                MultiSelectionPicker(
                    title: "대원 선택",
                    options: store.aarParticipants,
                    selectedIDs: Set(store.selectedParticipantIDs),
                    optionTitle: \.displayName,
                    canToggle: store.canToggleParticipant,
                    onToggle: store.toggleParticipantSelection,
                    selectedSummary: store.selectionSummary,
                    fieldBackground: InstructorColor.surfaceBase,
                    menuFillsFieldWidth: true
                )
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("aar.participants")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(InstructorColor.surfaceRaised)
            .zIndex(1)

            VStack(spacing: 1) {
                ForEach(0..<store.maximumVideoCount, id: \.self) { index in
                    Group {
                        if index < store.selectedParticipants.count {
                            let participant = store.selectedParticipants[index]
                            AARVideoTile(participant: participant, slotNumber: index + 1)
                        } else {
                            AAREmptyVideoSlot(slotNumber: index + 1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
        .accessibilityIdentifier("aar.videoPanel")
    }
}

private struct AAREmptyVideoSlot: View {
    let slotNumber: Int

    var body: some View {
        ZStack {
            InstructorColor.surfaceBase

            VStack(spacing: 6) {
                Image(systemName: "video.slash")
                    .font(.title3)
                Text("빈 영상 슬롯")
                    .font(.caption)
            }
            .foregroundStyle(InstructorColor.textSecondary)
        }
        .overlay(alignment: .topLeading) {
            Text("\(slotNumber)")
                .font(.caption.weight(.bold))
                .foregroundStyle(InstructorColor.textSecondary)
                .padding(10)
        }
        .accessibilityLabel("\(slotNumber)번 빈 영상 슬롯")
        .accessibilityIdentifier("aar.videoSlot.\(slotNumber).empty")
    }
}
