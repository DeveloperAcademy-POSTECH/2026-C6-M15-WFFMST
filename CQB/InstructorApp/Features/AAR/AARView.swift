import SwiftUI

struct AARView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    Group {
                        if store.aarMode == .movement {
                            AARMovementView()
                        } else {
                            AARVideoView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    settingsPanel
                        .frame(width: min(300, max(220, geometry.size.width * 0.25)))
                }

                timeline
            }
        }
        .padding()
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("설정값").font(.title2.bold())
                    Divider()
                    Text("표시 대상").font(.headline)
                    Label("팀 1 (MVP)", systemImage: "person.3")

                    MultiSelectionMenu(
                        title: store.selectionSummary,
                        options: store.participants,
                        selectedIDs: store.selectedParticipantIDs,
                        optionTitle: \.displayName,
                        canToggle: store.canToggleParticipant,
                        onToggle: store.toggleParticipantSelection,
                        onSelectAll: selectAllAction
                    )
                    .accessibilityIdentifier("aar.participants")

                    Text("선택된 대원: \(store.selectedParticipants.count)명")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Toggle("대원 바디캠", isOn: Binding(
                        get: { store.aarMode == .video },
                        set: { store.changeAARMode(to: $0 ? .video : .movement) }
                    ))
                    .accessibilityIdentifier("aar.bodycam")

                    Text(store.aarMode == .video ? "영상 모드 · 최대 \(store.maximumVideoCount)명" : "동선 모드")
                        .font(.subheadline)

                    Text("화면 확인용 임시 설정: 영상은 처음 \(store.maximumVideoCount)명이 선택됩니다. 모드별 선택과 공통 시간 위치를 유지합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let notice = store.aarNotice {
                        Text(notice).font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ActionButton("AAR 종료", action: store.finishAAR)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("aar.finish")
        }
    }

    private var selectAllAction: (() -> Void)? {
        guard store.canSelectAllParticipants else { return nil }
        return { store.selectAllParticipants() }
    }

    private var timeline: some View {
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

#Preview("AAR 동선") {
    let store = InstructorStore()
    store.openSessionCreation()
    store.createSession()
    store.startTraining()
    store.finishTraining()
    return AARView().environment(store)
}

#Preview("AAR 영상") {
    let store = InstructorStore()
    store.openSessionCreation()
    store.createSession()
    store.startTraining()
    store.finishTraining()
    store.changeAARMode(to: .video)
    return AARView().environment(store)
}
