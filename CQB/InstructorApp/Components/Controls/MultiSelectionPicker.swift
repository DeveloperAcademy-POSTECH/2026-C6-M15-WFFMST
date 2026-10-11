import CQBDesignSystem
import SwiftUI

struct MultiSelectionPicker<Option: Identifiable>: View {
    let title: String
    let options: [Option]
    let selectedIDs: Set<Option.ID>
    let optionTitle: (Option) -> String
    let optionColor: (Option) -> Color?
    let canToggle: (Option.ID) -> Bool
    let onToggle: (Option.ID) -> Void
    var onSelectAll: (() -> Void)? = nil

    init(
        title: String,
        options: [Option],
        selectedIDs: Set<Option.ID>,
        optionTitle: @escaping (Option) -> String,
        optionColor: @escaping (Option) -> Color? = { _ in nil },
        canToggle: @escaping (Option.ID) -> Bool,
        onToggle: @escaping (Option.ID) -> Void,
        onSelectAll: (() -> Void)? = nil
    ) {
        self.title = title
        self.options = options
        self.selectedIDs = selectedIDs
        self.optionTitle = optionTitle
        self.optionColor = optionColor
        self.canToggle = canToggle
        self.onToggle = onToggle
        self.onSelectAll = onSelectAll
    }

    var body: some View {
        SelectionDropdown(
            isEnabled: !options.isEmpty
        ) { isExpanded in
            SelectionFieldLabel(
                text: selectionSummary,
                isPlaceholder: selectedIDs.isEmpty,
                isExpanded: isExpanded
            )
        } content: { _ in
            SelectionMenuList(
                options: options,
                optionTitle: optionTitle,
                optionColor: optionColor,
                isSelected: selectedIDs.contains,
                canSelect: canToggle,
                onSelect: onToggle,
                footerTitle: onSelectAll == nil ? nil : "전체 선택",
                onFooterSelect: onSelectAll
            )
        }
        .accessibilityLabel(title)
        .accessibilityValue(selectionSummary)
    }

    private var selectionSummary: String {
        let selectedTitles = options
            .filter { selectedIDs.contains($0.id) }
            .map(optionTitle)

        guard !selectedTitles.isEmpty else {
            return title
        }

        return selectedTitles.joined(separator: ", ")
    }
}
