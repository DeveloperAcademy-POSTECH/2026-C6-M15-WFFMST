import SwiftUI

struct AARVideoView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch store.selectedParticipants.count {
                case 0:
                    ContentUnavailableView("표시할 대원을 선택하세요", systemImage: "video.slash",
                                           description: Text("오른쪽 표시 대상 메뉴에서 대원을 선택할 수 있습니다."))
                case 1:
                    videoRow(store.selectedParticipants)
                case 2:
                    VStack(spacing: 12) {
                        ForEach(store.selectedParticipants) { participant in
                            videoPlaceholder(participant)
                        }
                    }
                case 3:
                    VStack(spacing: 12) {
                        videoRow(Array(store.selectedParticipants.prefix(2)))
                        videoRow(Array(store.selectedParticipants.suffix(1)))
                            .frame(width: max(0, (geometry.size.width - 12) / 2))
                    }
                default:
                    VStack(spacing: 12) {
                        videoRow(Array(store.selectedParticipants.prefix(2)))
                        videoRow(Array(store.selectedParticipants.dropFirst(2)))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func videoRow(_ participants: [DemoParticipant]) -> some View {
        HStack(spacing: 12) {
            ForEach(participants) { participant in
                videoPlaceholder(participant)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func videoPlaceholder(_ participant: DemoParticipant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CAM \(participant.number) · \(participant.displayName)").font(.headline)
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Image(systemName: "video.slash").font(.largeTitle)
                Text("영상 표시 영역").font(.headline)
                Text("샘플 화면 · 영상 재생 미구현")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("aar.video.\(participant.id)")
    }
}

#Preview("3명 영상 배치") {
    let store = InstructorStore()
    store.openSessionCreation()
    store.createSession()
    store.startTraining()
    store.finishTraining()
    store.changeAARMode(to: .video)
    store.toggleParticipantSelection("member-4")
    return AARVideoView().environment(store)
}
