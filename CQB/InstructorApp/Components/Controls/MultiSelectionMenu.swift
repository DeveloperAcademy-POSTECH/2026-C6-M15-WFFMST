import SwiftUI

struct MultiSelectionMenu<Option: Identifiable>: View {
    let title: String
    let options: [Option]
    let selectedIDs: Set<Option.ID>
    let optionTitle: (Option) -> String
    let canToggle: (Option.ID) -> Bool
    let onToggle: (Option.ID) -> Void
    var onSelectAll: (() -> Void)? = nil

    var body: some View {
        Menu {
            ForEach(options) { option in
                ActionButton(optionTitle(option),
                             systemImage: selectedIDs.contains(option.id) ? "checkmark" : nil) {
                    onToggle(option.id)
                }
                .disabled(!canToggle(option.id))
            }
            if let onSelectAll {
                Divider()
                ActionButton("전체 대원", action: onSelectAll)
            }
        } label: {
            Label(title, systemImage: "chevron.down")
        }
        .disabled(options.isEmpty)
    }
}
