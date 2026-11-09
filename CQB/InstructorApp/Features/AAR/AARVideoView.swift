import AVFoundation
import CQBCore
import CQBDesignSystem
import SwiftUI

struct AARVideoView: View {
    @Environment(InstructorStore.self) private var store

    private let tileSpacing = AARLayout.videoGridGap

    var body: some View {
        let selectedParticipants = Array(store.selectedParticipants.prefix(store.maximumVideoCount))

        VStack(spacing: tileSpacing) {
            HStack(spacing: 12) {
                Text("영상 비교분석 화면")
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(InstructorColor.aarPanelLabel)

                Spacer()

                Button(action: store.showAARFloorPlan) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(InstructorColor.aarContentPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("도면 화면으로 돌아가기")
                .accessibilityIdentifier("aar.closeVideoScreen")
            }
            .padding(.horizontal, 16)
            .frame(height: AARLayout.contentHeaderHeight)
            .background(InstructorColor.aarMapSurface)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 16
                )
            )

            GeometryReader { geometry in
                let halfWidth = max(0, (geometry.size.width - tileSpacing) / 2)
                let halfHeight = max(0, (geometry.size.height - tileSpacing) / 2)

                Group {
                    switch selectedParticipants.count {
                    case 0:
                        emptySelection
                    case 1:
                        AARVideoTile(participant: selectedParticipants[0], slotNumber: 1)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    case 2:
                        HStack(spacing: tileSpacing) {
                            ForEach(Array(selectedParticipants.enumerated()), id: \.element.id) { index, participant in
                                AARVideoTile(participant: participant, slotNumber: index + 1)
                                    .frame(width: halfWidth, height: geometry.size.height)
                            }
                        }
                    case 3:
                        VStack(spacing: tileSpacing) {
                            HStack(spacing: tileSpacing) {
                                ForEach(Array(selectedParticipants.prefix(2).enumerated()), id: \.element.id) { index, participant in
                                    AARVideoTile(participant: participant, slotNumber: index + 1)
                                        .frame(width: halfWidth, height: halfHeight)
                                }
                            }

                            AARVideoTile(participant: selectedParticipants[2], slotNumber: 3)
                                .frame(width: halfWidth, height: halfHeight)
                        }
                        .frame(maxWidth: .infinity)
                    default:
                        VStack(spacing: tileSpacing) {
                            ForEach(0..<2, id: \.self) { row in
                                HStack(spacing: tileSpacing) {
                                    ForEach(0..<2, id: \.self) { column in
                                        let index = row * 2 + column
                                        let participant = selectedParticipants[index]
                                        AARVideoTile(participant: participant, slotNumber: index + 1)
                                            .frame(width: halfWidth, height: halfHeight)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .accessibilityIdentifier("aar.videoScreen")
    }

    private var emptySelection: some View {
        ContentUnavailableView(
            "표시할 대원을 선택하세요",
            systemImage: "video.slash",
            description: Text("도면 화면에서 대원 마커를 선택할 수 있습니다.")
        )
        .foregroundStyle(InstructorColor.aarContentSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.aarVideoSlotSurface)
    }
}

struct AARVideoTile: View {
    @Environment(InstructorStore.self) private var store
    @Environment(AARStore.self) private var aarStore

    let participant: InstructorParticipant
    let slotNumber: Int

    var body: some View {
        videoContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                cameraLabel
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                closeButton
            }
            .overlay(alignment: .bottomLeading) {
                muteButton
            }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("영상 \(slotNumber)번, \(participant.name), \(accessibilityStatus)")
        .accessibilityIdentifier("aar.video.\(participant.id)")
    }

    private var closeButton: some View {
        Button {
            store.toggleParticipantSelection(participant.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(InstructorColor.aarContentPrimary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(participant.name) 영상 닫기")
        .accessibilityIdentifier("aar.video.\(participant.id).close")
    }

    private var muteButton: some View {
        let isMuted = store.isParticipantMuted(participant.id)

        return Button {
            store.toggleParticipantMute(participant.id)
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(InstructorColor.aarContentPrimary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel(isMuted
            ? "\(participant.name) 영상 소리 켜기"
            : "\(participant.name) 영상 소리 끄기")
        .accessibilityValue(isMuted ? "음소거됨" : "소리 켜짐")
        .accessibilityIdentifier("aar.video.\(participant.id).mute")
    }

    @ViewBuilder
    private var videoContent: some View {
        switch aarStore.videos[participant.id] {
        case .ready(let player, _):
            AARPlayerView(
                player: player,
                isMuted: store.isParticipantMuted(participant.id)
            )
                .overlay {
                    if aarStore.videoFrame(for: participant.id) == .notStarted {
                        statusMessage("녹화 시작 전")
                    }
                }
        case .unavailable(let reason):
            statusMessage(reason)
        case .loading, nil:
            ZStack {
                InstructorColor.aarVideoSlotSurface
                ProgressView("영상을 불러오는 중")
                    .foregroundStyle(InstructorColor.aarContentSecondary)
            }
        }
    }

    private func statusMessage(_ text: String) -> some View {
        ZStack {
            InstructorColor.aarVideoSlotSurface.opacity(0.94)
            Label(text, systemImage: "video.slash")
                .dsTextStyle(DSTypography.bodyRegular12)
                .foregroundStyle(InstructorColor.aarContentSecondary)
        }
    }

    private var accessibilityStatus: String {
        switch aarStore.videos[participant.id] {
        case .ready: "녹화 영상"
        case .unavailable(let reason): reason
        case .loading, nil: "영상을 불러오는 중"
        }
    }

    private var cameraLabel: some View {
        HStack(spacing: 6) {
            Text("\(slotNumber)  \(participant.name)")
                .dsTextStyle(DSTypography.bodyRegular12)
                .fontWeight(.bold)
                .foregroundStyle(InstructorColor.aarContentPrimary)

            Circle()
                .fill(InstructorColor.aarActionPrimary)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(InstructorColor.aarMapSurface.opacity(0.94))
        .clipShape(.rect(cornerRadius: 8))
    }
}

/// `AVPlayer`의 화면을 비율을 유지해 그린다.
private struct AARPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let isMuted: Bool

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        player.isMuted = isMuted
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        if player.isMuted != isMuted { player.isMuted = isMuted }
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

#if DEBUG
@MainActor
private func aarVideoPreview(selectedCount: Int) -> some View {
    let store = InstructorPreviewFixture.store(floorPlan: InstructorFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    ), phase: .aar)
    for participant in store.participants.prefix(selectedCount).reversed() {
        store.toggleParticipantSelection(participant.id)
    }
    store.openAARVideoScreen()

    return AARVideoView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_008, height: 896)
        .preferredColorScheme(.dark)
}

#Preview("AAR 영상 · 0명") {
    aarVideoPreview(selectedCount: 0)
}

#Preview("AAR 영상 · 1명") {
    aarVideoPreview(selectedCount: 1)
}

#Preview("AAR 영상 · 2명") {
    aarVideoPreview(selectedCount: 2)
}

#Preview("AAR 영상 · 3명") {
    aarVideoPreview(selectedCount: 3)
}

#Preview("AAR 영상 · 4명") {
    aarVideoPreview(selectedCount: 4)
}
#endif
