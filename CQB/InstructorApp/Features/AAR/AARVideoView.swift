import AVFoundation
import CQBCore
import CQBDesignSystem
import SwiftUI

struct AARVideoView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(AARStore.self) private var aarStore

    private let tileSpacing: CGFloat = 12

    var body: some View {
        let selectedParticipants = Array(store.selectedParticipants.prefix(store.maximumVideoCount))

        GeometryReader { geometry in
            let halfWidth = max(0, (geometry.size.width - tileSpacing) / 2)
            let halfHeight = max(0, (geometry.size.height - tileSpacing) / 2)

            Group {
                switch selectedParticipants.count {
                case 0:
                    emptySelection
                case 1:
                    AARVideoTile(participant: selectedParticipants[0])
                        .frame(width: geometry.size.width, height: geometry.size.height)
                case 2:
                    VStack(spacing: tileSpacing) {
                        ForEach(selectedParticipants) { participant in
                            AARVideoTile(participant: participant)
                                .frame(width: geometry.size.width, height: halfHeight)
                        }
                    }
                case 3:
                    VStack(spacing: tileSpacing) {
                        HStack(spacing: tileSpacing) {
                            ForEach(selectedParticipants.prefix(2)) { participant in
                                AARVideoTile(participant: participant)
                                    .frame(width: halfWidth, height: halfHeight)
                            }
                        }

                        AARVideoTile(participant: selectedParticipants[2])
                            .frame(width: halfWidth, height: halfHeight)
                    }
                    .frame(maxWidth: .infinity)
                default:
                    VStack(spacing: tileSpacing) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: tileSpacing) {
                                ForEach(0..<2, id: \.self) { column in
                                    let participant = selectedParticipants[row * 2 + column]
                                    AARVideoTile(participant: participant)
                                        .frame(width: halfWidth, height: halfHeight)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // 선택한 대원의 영상만 받는다. 동선 모드로 바꾸면 영상을 멈춘다.
        .onChange(of: selectedParticipants.map(\.id), initial: true) { _, ids in
            aarStore.showVideos(for: ids)
        }
        .onDisappear { aarStore.showVideos(for: []) }
    }

    private var emptySelection: some View {
        ContentUnavailableView(
            "표시할 대원을 선택하세요",
            systemImage: "video.slash",
            description: Text("오른쪽 표시 대상 메뉴에서 대원을 선택할 수 있습니다.")
        )
        .foregroundStyle(InstructorColor.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
    }

}

private struct AARVideoTile: View {
    @Environment(AARStore.self) private var aarStore

    let participant: InstructorParticipant

    private let cameraAspectRatio: CGFloat = 1_672 / 941

    var body: some View {
        GeometryReader { geometry in
            let videoSize = fittedVideoSize(in: geometry.size)

            ZStack {
                InstructorColor.canvas

                videoContent
                    .frame(width: videoSize.width, height: videoSize.height)
                    .overlay(alignment: .topLeading) {
                        cameraLabel
                            .padding(12)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(.rect(cornerRadius: 4))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CAM \(participant.number), \(accessibilityStatus)")
        .accessibilityIdentifier("aar.video.\(participant.id)")
    }

    @ViewBuilder
    private var videoContent: some View {
        switch aarStore.videos[participant.id] {
        case .ready(let player, _):
            // AAR에서는 화면 가장자리의 정보도 필요하므로 원본 프레임 전체를 보존한다.
            AARPlayerView(player: player)
                .overlay {
                    if aarStore.videoFrame(for: participant.id) == .notStarted {
                        statusMessage("녹화 시작 전")
                    }
                }
        case .unavailable(let reason):
            statusMessage(reason)
        case .loading, nil:
            ZStack {
                InstructorColor.surfaceBase
                ProgressView("영상을 불러오는 중")
                    .foregroundStyle(InstructorColor.textSecondary)
            }
        }
    }

    private func statusMessage(_ text: String) -> some View {
        ZStack {
            InstructorColor.surfaceBase.opacity(0.94)
            Label(text, systemImage: "video.slash")
                .font(DSTypography.label)
                .foregroundStyle(InstructorColor.textSecondary)
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
        HStack(spacing: 4) {
            Text("CAM \(participant.number)")
                .font(DSTypography.label)
                .foregroundStyle(InstructorColor.textPrimary)

            Circle()
                .fill(InstructorColor.teamOne)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(InstructorColor.surfaceBase.opacity(0.94))
        .clipShape(.rect(cornerRadius: 4))
    }

    private func fittedVideoSize(in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }

        if container.width / container.height > cameraAspectRatio {
            return CGSize(
                width: container.height * cameraAspectRatio,
                height: container.height
            )
        }

        return CGSize(
            width: container.width,
            height: container.width / cameraAspectRatio
        )
    }
}

/// `AVPlayer`의 화면을 비율을 유지해 그린다.
private struct AARPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

#if DEBUG
@MainActor
private func aarVideoPreview(selectedCount: Int) -> some View {
    let store = InstructorPreviewFixture.store(floorPlan: DemoFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    ), phase: .aar)
    for participant in store.participants.dropFirst(selectedCount) {
        store.toggleParticipantSelection(participant.id)
    }
    store.changeAARMode(to: .video)

    return AARVideoView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_008, height: 896)
        .preferredColorScheme(.dark)
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
