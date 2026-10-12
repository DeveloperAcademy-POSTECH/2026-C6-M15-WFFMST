import CQBDesignSystem
import SwiftUI

struct AARSettingsView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("설정값")
                .font(DSTypography.h2)
                .foregroundStyle(InstructorColor.textPrimary)

            rule

            Text("표시 대상")
                .font(DSTypography.h3)
                .foregroundStyle(InstructorColor.textSecondary)

            MultiSelectionPicker(
                title: "대원 선택",
                options: store.participants,
                selectedIDs: store.selectedParticipantIDs,
                optionTitle: \.displayName,
                canToggle: store.canToggleParticipant,
                onToggle: store.toggleParticipantSelection,
                selectedSummary: store.selectionSummary,
                fieldBackground: InstructorColor.surfaceRaised,
                menuFillsFieldWidth: true,
                onSelectAll: selectAllAction
            )
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("aar.participants")

            rule

            HStack {
                Text("대원 바디캠")
                    .font(DSTypography.h3)
                    .foregroundStyle(InstructorColor.textPrimary)

                Spacer()

                Toggle(
                    "대원 바디캠",
                    isOn: Binding(
                        get: { store.aarMode == .video },
                        set: { store.changeAARMode(to: $0 ? .video : .movement) }
                    )
                )
                .labelsHidden()
                .toggleStyle(InstructorCompactToggleStyle())
                .accessibilityIdentifier("aar.bodycam")
            }
            .frame(height: 26)

            Text(store.aarMode == .video ? "ON" : "OFF")
                .font(DSTypography.caption)
                .foregroundStyle(InstructorColor.actionPrimary)

            if let notice = store.aarNotice {
                Text(notice)
                    .font(DSTypography.caption)
                    .foregroundStyle(InstructorColor.actionPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            rule

            Spacer(minLength: 0)

            ActionButton(
                "AAR 종료",
                tone: .secondary,
                density: .compact,
                fillsWidth: true,
                action: store.finishAAR
            )
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .accessibilityIdentifier("aar.finish")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(InstructorColor.borderDefault)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var selectAllAction: (() -> Void)? {
        guard store.canSelectAllParticipants else { return nil }
        return { store.selectAllParticipants() }
    }
}

private struct InstructorCompactToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(InstructorColor.borderDefault)
                .frame(width: 51, height: 26)
                .overlay {
                    Circle()
                        .fill(InstructorColor.actionPrimary)
                        .frame(width: 19, height: 19)
                        .offset(x: configuration.isOn ? 11 : -11)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

#Preview("AAR 설정 · 동선") {
    let store = InstructorStore(floorPlans: [
        DemoFloorPlan(
            id: "preview-plan",
            name: "훈련장 A 도면",
            fileName: "훈련장 A 도면.png",
            referenceDistance: 15
        )
    ])
    store.openSessionCreation()
    store.createSession()
    store.startTraining()
    store.finishTraining()

    return DropdownHost {
        AARSettingsView()
            .environment(store)
            .frame(width: 298, height: 896)
    }
    .padding(24)
    .background(InstructorColor.canvas)
    .preferredColorScheme(.dark)
}
