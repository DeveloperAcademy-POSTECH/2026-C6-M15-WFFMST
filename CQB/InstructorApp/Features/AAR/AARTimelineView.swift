import SwiftUI

struct AARTimelineView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 16) {
                // 실제 재생은 이번 이슈의 범위 밖이므로 버튼을 비활성화한다.
                ActionButton("재생 미구현", systemImage: "play.fill", action: {})
                    .disabled(true)
                Text("1×").foregroundStyle(.secondary)
                Text(timeLabel(store.playbackPosition)).monospacedDigit()

                Slider(value: Binding(
                    get: { store.playbackPosition },
                    set: store.setPlaybackPosition
                ), in: 0...store.playbackDuration) {
                    Text("복기 시간 위치")
                }
                .accessibilityValue(timeLabel(store.playbackPosition))
                .accessibilityIdentifier("aar.timeline")

                Text(timeLabel(store.playbackDuration)).monospacedDigit()
            }
            Text("시간 위치만 변경합니다 · 영상 재생 및 동선 동기화는 미구현입니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
