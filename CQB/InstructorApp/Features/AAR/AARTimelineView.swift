import CQBDesignSystem
import SwiftUI

struct AARTimelineView: View {
    @Environment(AARStore.self) private var aarStore

    var body: some View {
        HStack(spacing: 12) {
            Button(action: aarStore.togglePlayback) {
                Text(aarStore.isPlaying ? "❚❚" : "▶")
                    .font(playbackFont)
                    .foregroundStyle(InstructorColor.playerPlay)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!aarStore.canPlay)
            .accessibilityLabel(aarStore.isPlaying ? "일시정지" : "재생")

            Text(timeLabel(aarStore.playbackPosition))
                .frame(minWidth: 53)

            AARPlaybackTrack(
                value: aarStore.playbackPosition,
                range: 0...aarStore.playbackDuration,
                onChange: aarStore.setPlaybackPosition
            )
            .accessibilityIdentifier("aar.timeline")

            Text(timeLabel(aarStore.playbackDuration))
                .frame(width: 54)
        }
        .font(playbackFont)
        .foregroundStyle(InstructorColor.textPrimary)
        .monospacedDigit()
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstructorColor.playerSurface)
        .clipShape(.rect(cornerRadius: 4))
    }

    private var playbackFont: Font {
        DSFonts.register()
        return .custom("NotoSansKR-Bold", size: 16, relativeTo: .body)
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct AARPlaybackTrack: View {
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(InstructorColor.borderDefault)
                    .frame(height: 3)

                Capsule()
                    .fill(InstructorColor.actionPrimary)
                    .frame(width: geometry.size.width * progress, height: 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, width: geometry.size.width)
                    }
            )
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        .accessibilityElement()
        .accessibilityLabel("복기 시간 위치")
        .accessibilityValue(timeLabel(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(value + 10)
            case .decrement: onChange(value - 10)
            @unknown default: break
            }
        }
    }

    private var progress: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    private func updateValue(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let fraction = min(max(Double(x / width), 0), 1)
        onChange(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

#Preview("AAR 재생바") {
    AARTimelineView()
        .environment(AARStore())
        .frame(width: 1_318, height: 48)
        .preferredColorScheme(.dark)
}
