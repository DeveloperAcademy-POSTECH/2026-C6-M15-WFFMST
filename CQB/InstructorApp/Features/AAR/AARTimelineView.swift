import CQBDesignSystem
import SwiftUI

struct AARTimelineView: View {
    @Environment(AARStore.self) private var aarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AARPlaybackTrack(
                value: aarStore.playbackPosition,
                range: 0...aarStore.playbackDuration,
                onChange: aarStore.setPlaybackPosition
            )
            .frame(height: 44)
            .padding(.top, 21)
            .padding(.horizontal, AARLayout.timelineHorizontalPadding)
            .accessibilityIdentifier("aar.timeline")

            HStack(spacing: 32) {
                skipButton(
                    seconds: -10,
                    systemImage: "10.arrow.trianglehead.counterclockwise",
                    accessibilityLabel: "10초 전"
                )

                Button(action: aarStore.togglePlayback) {
                    Image(systemName: aarStore.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(InstructorColor.playerPlay)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!aarStore.canPlay)
                .accessibilityLabel(aarStore.isPlaying ? "일시정지" : "재생")

                skipButton(
                    seconds: 10,
                    systemImage: "10.arrow.trianglehead.clockwise",
                    accessibilityLabel: "10초 후"
                )

                Text("\(timeLabel(aarStore.playbackPosition)) / \(timeLabel(aarStore.playbackDuration))")
                    .dsTextStyle(DSTypography.bodyRegular24)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .monospacedDigit()
            }
            .padding(.top, 12)
            .padding(.leading, AARLayout.timelineHorizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.playerSurface)
    }

    private func skipButton(
        seconds: Double,
        systemImage: String,
        accessibilityLabel: String
    ) -> some View {
        Button {
            aarStore.skipPlayback(by: seconds)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(InstructorColor.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!aarStore.canPlay)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(seconds < 0 ? "aar.skipBackward10" : "aar.skipForward10")
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
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
                Rectangle()
                    .fill(InstructorColor.aarTimelineTrack)
                    .frame(height: 4)

                Rectangle()
                    .fill(InstructorColor.aarTimelineProgress)
                    .frame(width: geometry.size.width * progress, height: 4)

                Circle()
                    .fill(InstructorColor.aarTimelineProgress)
                    .frame(width: 16, height: 16)
                    .offset(x: thumbOffset(for: geometry.size.width))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, width: geometry.size.width)
                    }
            )
        }
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

    private func thumbOffset(for width: CGFloat) -> CGFloat {
        max(0, width - 16) * progress
    }

    private func updateValue(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let fraction = min(max(Double(x / width), 0), 1)
        onChange(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

#Preview("AAR 재생바") {
    AARTimelineView()
        .environment(AARStore())
        .frame(width: 1_366, height: AARLayout.timelineHeight)
        .preferredColorScheme(.dark)
}
