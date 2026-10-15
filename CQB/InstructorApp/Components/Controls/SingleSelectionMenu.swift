import CQBDesignSystem
import SwiftUI

struct SingleSelectionMenu<Option: Identifiable>: View {
    let title: String
    let options: [Option]
    let selection: Option.ID?
    let optionTitle: (Option) -> String
    let optionColor: (Option) -> Color?
    let fieldBackground: Color
    let menuFillsFieldWidth: Bool
    let onSelect: (Option.ID?) -> Void

    init(
        title: String,
        options: [Option],
        selection: Option.ID?,
        optionTitle: @escaping (Option) -> String,
        optionColor: @escaping (Option) -> Color? = { _ in nil },
        fieldBackground: Color = InstructorColor.surfaceBase,
        menuFillsFieldWidth: Bool = false,
        onSelect: @escaping (Option.ID?) -> Void
    ) {
        self.title = title
        self.options = options
        self.selection = selection
        self.optionTitle = optionTitle
        self.optionColor = optionColor
        self.fieldBackground = fieldBackground
        self.menuFillsFieldWidth = menuFillsFieldWidth
        self.onSelect = onSelect
    }

    var body: some View {
        SelectionDropdown(
            isEnabled: !options.isEmpty
        ) { isExpanded in
            SelectionFieldLabel(
                text: selectedTitle,
                color: selectedOption.flatMap(optionColor),
                isPlaceholder: selection == nil,
                isExpanded: isExpanded,
                backgroundColor: fieldBackground
            )
        } content: { dismissImmediately in
            SelectionMenuList(
                options: options,
                optionTitle: optionTitle,
                optionColor: optionColor,
                isSelected: { selection == $0 },
                canSelect: { _ in true },
                onSelect: { id in
                    dismissImmediately()
                    onSelect(id)
                },
                fillsAvailableWidth: menuFillsFieldWidth
            )
        }
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
    }

    private var selectedTitle: String {
        guard let selectedOption else {
            return "선택하세요"
        }
        return optionTitle(selectedOption)
    }

    private var selectedOption: Option? {
        guard let selection else { return nil }
        return options.first(where: { $0.id == selection })
    }
}
