import CQBDesignSystem
import SwiftUI

struct AARVideoView: View {
    @Environment(InstructorStore.self) private var store

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
                    CameraPlaceholderTile(participant: selectedParticipants[0])
                        .frame(width: geometry.size.width, height: geometry.size.height)
                case 2:
                    VStack(spacing: tileSpacing) {
                        ForEach(selectedParticipants) { participant in
                            CameraPlaceholderTile(participant: participant)
                                .frame(width: geometry.size.width, height: halfHeight)
                        }
                    }
                case 3:
                    VStack(spacing: tileSpacing) {
                        HStack(spacing: tileSpacing) {
                            ForEach(selectedParticipants.prefix(2)) { participant in
                                CameraPlaceholderTile(participant: participant)
                                    .frame(width: halfWidth, height: halfHeight)
                            }
                        }

                        CameraPlaceholderTile(participant: selectedParticipants[2])
                            .frame(width: halfWidth, height: halfHeight)
                    }
                    .frame(maxWidth: .infinity)
                default:
                    VStack(spacing: tileSpacing) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: tileSpacing) {
                                ForEach(0..<2, id: \.self) { column in
                                    let participant = selectedParticipants[row * 2 + column]
                                    CameraPlaceholderTile(participant: participant)
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

private struct CameraPlaceholderTile: View {
    let participant: InstructorParticipant

    private let cameraAspectRatio: CGFloat = 1_672 / 941

    var body: some View {
        GeometryReader { geometry in
            let videoSize = fittedVideoSize(in: geometry.size)

            ZStack {
                InstructorColor.canvas

                Image("InstructorCameraPlaceholder")
                    .resizable()
                    // AAR에서는 화면 가장자리의 정보도 필요하므로 원본 프레임 전체를 보존한다.
                    .scaledToFit()
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
        .accessibilityLabel("CAM \(participant.number), 샘플 영상 자리표시자")
        .accessibilityIdentifier("aar.video.\(participant.id)")
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
