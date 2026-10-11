import SwiftUI

struct AARSettingsView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        DropdownHost {
            VStack(alignment: .leading, spacing: 20) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("설정값").font(.title2.bold())
                        Divider()
                        Text("표시 대상").font(.headline)
                        Label("팀 1 (MVP)", systemImage: "person.3")

                        MultiSelectionPicker(
                            title: store.selectionSummary,
                            options: store.participants,
                            selectedIDs: store.selectedParticipantIDs,
                            optionTitle: \.displayName,
                            canToggle: store.canToggleParticipant,
                            onToggle: store.toggleParticipantSelection,
                            onSelectAll: selectAllAction
                        )
                        .accessibilityIdentifier("aar.participants")

                        Text("선택된 대원: \(store.selectedParticipantIDs.count)명")
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

                        Text("동선과 영상은 같은 표시 대상을 유지합니다. 영상 전환은 최대 \(store.maximumVideoCount)명까지 가능합니다.")
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
    }

    private var selectAllAction: (() -> Void)? {
        guard store.canSelectAllParticipants else { return nil }
        return { store.selectAllParticipants() }
    }
}
