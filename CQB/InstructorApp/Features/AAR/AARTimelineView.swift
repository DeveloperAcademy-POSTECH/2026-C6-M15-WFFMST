import CQBDesignSystem
import SwiftUI

struct AARTimelineView: View {
    @Environment(AARStore.self) private var aarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AARPlaybackTrack(
                value: aarStore.playbackPosition,
                range: 0...aarStore.playbackDuration,
                soundEvents: aarStore.soundEvents,
                onChange: aarStore.setPlaybackPosition,
                onSelectSoundEvent: aarStore.jumpToSoundEvent
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
                    .foregroundStyle(InstructorColor.aarContentPrimary)
                    .monospacedDigit()
            }
            .padding(.top, 12)
            .padding(.leading, AARLayout.timelineHorizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.aarPlayerSurface)
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
                .foregroundStyle(InstructorColor.aarContentPrimary)
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
    let soundEvents: [AARSoundEvent]
    let onChange: (Double) -> Void
    let onSelectSoundEvent: (AARSoundEvent) -> Void

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
            .overlay(alignment: .leading) {
                soundEventMarkers(width: geometry.size.width)
            }
        }
    }

    /// 재생바 위의 큰 소리 표시(Figma `iPad 06 · AAR` 노란 핀). 누르면 그 시각으로 이동한다.
    /// 핀 끝(높이 29 중 28)이 재생바 아래 끝에 닿도록 44pt 누름 영역 가운데에서 11.5 올린다.
    private func soundEventMarkers(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(visibleSoundEvents) { event in
                Button {
                    onSelectSoundEvent(event)
                } label: {
                    Image("AARSoundEventMarker")
                        .renderingMode(.original)
                        .resizable()
                        .frame(width: 10, height: 29)
                        .offset(y: -11.5)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .offset(x: markerOffset(for: event.time, width: width) - 22)
                .accessibilityLabel("큰 소리 \(timeLabel(event.time)), 대원 \(event.participantIDs.count)명")
                .accessibilityHint("이 시각으로 이동합니다.")
                .accessibilityIdentifier("aar.soundEvent.\(Int(event.time * 1_000))")
            }
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }

    private var visibleSoundEvents: [AARSoundEvent] {
        guard range.upperBound > range.lowerBound else { return [] }
        return soundEvents.filter { range.contains($0.time) }
    }

    private func markerOffset(for time: Double, width: CGFloat) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let fraction = (time - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(fraction) * width
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

#Preview("AAR 재생바 · 큰 소리 표시", traits: .landscapeLeft) {
    AARSoundEventTrackPreview()
        .preferredColorScheme(.dark)
}

/// 데모 영상(30초)과 같은 큰 소리 이벤트로 재생바 표시를 확인한다. 마커를 누르면 그 시각으로 이동한다.
private struct AARSoundEventTrackPreview: View {
    @State private var position = 10.0
    private let events = [
        AARSoundEvent(time: 6.20, participantIDs: ["1", "2", "3", "4"], isCorroborated: true),
        AARSoundEvent(time: 14.80, participantIDs: ["2", "5", "6"], isCorroborated: true),
        AARSoundEvent(time: 26.00, participantIDs: ["1", "4"], isCorroborated: true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AARPlaybackTrack(
                value: position,
                range: 0...30,
                soundEvents: events,
                onChange: { position = min(max($0, 0), 30) },
                onSelectSoundEvent: { position = $0.time }
            )
            .frame(height: 44)

            Text(String(format: "재생 위치 %.1f초", position))
                .dsTextStyle(DSTypography.bodyRegular24)
                .foregroundStyle(InstructorColor.aarContentPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, AARLayout.timelineHorizontalPadding)
        .padding(.vertical, 21)
        .frame(width: 1_366, alignment: .leading)
        .background(InstructorColor.aarPlayerSurface)
    }
}
