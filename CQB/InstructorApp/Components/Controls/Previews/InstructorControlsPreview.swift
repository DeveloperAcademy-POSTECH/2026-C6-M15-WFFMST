#if DEBUG
import CQBDesignSystem
import SwiftUI

private struct InstructorControlsPreview: View {
    @State private var emptyText = ""
    @State private var filledText = "훈련장 A"
    @State private var selectedPlanID: Int? = 1
    @State private var selectedTeamIDs: Set<Int> = [1]

    private let plans = [
        PreviewFloorPlan(id: 1, name: "훈련장 A 도면"),
        PreviewFloorPlan(id: 2, name: "훈련장 B 도면")
    ]

    private let teams = [
        PreviewTeam(id: 1, name: "팀 1", color: DSColor.team1),
        PreviewTeam(id: 2, name: "팀 2", color: DSColor.team2),
        PreviewTeam(id: 3, name: "팀 3", color: DSColor.team3)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                previewSection("Primary button") {
                    ActionButton("훈련 시작", action: {})
                    ActionButton("훈련 시작", action: {})
                        .disabled(true)
                    ActionButton("도면 추가", systemImage: "plus", action: {})
                }

                previewSection("Text field") {
                    InstructorTextField(
                        title: "훈련장 이름",
                        placeholder: "훈련장 이름을 입력하세요",
                        text: $emptyText
                    )
                    InstructorTextField(
                        title: "훈련장 이름",
                        placeholder: "훈련장 이름을 입력하세요",
                        text: $filledText
                    )
                    InstructorTextField(
                        title: "훈련장 이름",
                        placeholder: "훈련장 이름을 입력하세요",
                        text: $emptyText,
                        validationMessage: "이름을 입력해 주세요."
                    )
                    InstructorTextField(
                        title: "훈련장 이름",
                        placeholder: "훈련장 이름을 입력하세요",
                        text: $filledText
                    )
                    .disabled(true)
                    .opacity(0.55)
                }

                previewSection("Single selection") {
                    SingleSelectionMenu(
                        title: "훈련 도면",
                        options: plans,
                        selection: nil,
                        optionTitle: \.name,
                        onSelect: { _ in }
                    )
                    .frame(width: 250)
                    SingleSelectionMenu(
                        title: "훈련 도면",
                        options: plans,
                        selection: selectedPlanID,
                        optionTitle: \.name,
                        onSelect: { selectedPlanID = $0 }
                    )
                    .frame(width: 250)
                    SingleSelectionMenu(
                        title: "훈련 도면",
                        options: [PreviewFloorPlan](),
                        selection: Int?.none,
                        optionTitle: \.name,
                        onSelect: { _ in }
                    )
                    .frame(width: 250)
                }

                previewSection("Multiple selection") {
                    MultiSelectionPicker(
                        title: "팀 선택",
                        options: teams,
                        selectedIDs: selectedTeamIDs,
                        optionTitle: \.name,
                        optionColor: \.color,
                        canToggle: { _ in true },
                        onToggle: toggleTeam,
                        onSelectAll: selectAllTeams
                    )
                    .frame(width: 250)
                }

            }
            .frame(width: 544)
            .padding(32)
        }
        .background(DSColor.background)
        .preferredColorScheme(.dark)
    }

    private func previewSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DSTypography.h3)
                .foregroundStyle(DSColor.white)
            content()
        }
    }

    private func toggleTeam(_ id: Int) {
        if selectedTeamIDs.contains(id) {
            selectedTeamIDs.remove(id)
        } else {
            selectedTeamIDs.insert(id)
        }
    }

    private func selectAllTeams() {
        selectedTeamIDs = Set(teams.map(\.id))
    }
}

private struct PreviewFloorPlan: Identifiable {
    let id: Int
    let name: String
}

private struct PreviewTeam: Identifiable {
    let id: Int
    let name: String
    let color: Color
}

#Preview("Instructor controls") {
    DropdownHost {
        InstructorControlsPreview()
    }
}
#endif
