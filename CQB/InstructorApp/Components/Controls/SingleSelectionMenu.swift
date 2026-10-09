import SwiftUI

struct SingleSelectionMenu<Option: Identifiable>: View {
    let title: String
    let options: [Option]
    let selection: Option.ID?
    let optionTitle: (Option) -> String
    let onSelect: (Option.ID?) -> Void

    var body: some View {
        Picker(title, selection: Binding(get: { selection }, set: onSelect)) {
            Text("선택하세요").tag(Optional<Option.ID>.none)
            ForEach(options) { option in
                Text(optionTitle(option)).tag(Optional(option.id))
            }
        }
        .pickerStyle(.menu)
        .disabled(options.isEmpty)
    }
}
