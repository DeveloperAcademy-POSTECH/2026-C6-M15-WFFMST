import CQBDesignSystem
import SwiftUI

struct AARContentView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        Group {
            if store.aarScreen == .floorPlan {
                GeometryReader { geometry in
                    let availableWidth = max(geometry.size.width - AARLayout.contentGap, 0)
                    let videoPanelWidth = availableWidth / 4
                    let floorPlanWidth = availableWidth - videoPanelWidth

                    HStack(spacing: AARLayout.contentGap) {
                        AARMovementView()
                            .frame(width: floorPlanWidth, height: geometry.size.height)

                        AARVideoPanel()
                            .frame(width: videoPanelWidth, height: geometry.size.height)
                    }
                }
            } else {
                AARVideoView()
            }
        }
        .padding(.horizontal, AARLayout.outerHorizontalPadding)
    }
}

private struct AARVideoPanel: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.s12) {
                Text("전체화면 보기")
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(InstructorColor.aarPanelLabel)

                Spacer()

                Button(action: store.openAARVideoScreen) {
                    Image(systemName: "viewfinder")
                        .font(.title3)
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
            .padding(.leading, DSSpacing.s12)
            .frame(height: AARLayout.contentHeaderHeight)
            .background(InstructorColor.aarMapSurface)

            VStack(spacing: 0) {
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
        .background(InstructorColor.aarVideoSlotSurface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: DSRadius.large,
                topTrailingRadius: DSRadius.large
            )
        )
        .accessibilityIdentifier("aar.videoPanel")
    }
}

private struct AAREmptyVideoSlot: View {
    let slotNumber: Int

    var body: some View {
        ZStack {
            InstructorColor.aarVideoSlotSurface

            Text("대원을 선택시 영상 재생")
                .dsTextStyle(DSTypography.bodyRegular16)
                .foregroundStyle(InstructorColor.aarPlaceholderText)
        }
        .accessibilityLabel("\(slotNumber)번 빈 영상 슬롯")
        .accessibilityIdentifier("aar.videoSlot.\(slotNumber).empty")
    }
}
