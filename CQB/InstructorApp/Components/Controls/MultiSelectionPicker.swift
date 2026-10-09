import SwiftUI

struct MultiSelectionPicker<Option: Identifiable>: View {
    @State private var isPresented = false

    let title: String
    let options: [Option]
    let selectedIDs: Set<Option.ID>
    let optionTitle: (Option) -> String
    let canToggle: (Option.ID) -> Bool
    let onToggle: (Option.ID) -> Void
    var onSelectAll: (() -> Void)? = nil

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(title, systemImage: "chevron.down")
        }
        .disabled(options.isEmpty)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(spacing: 0) {
                HStack {
                    Text("표시 대상")
                        .font(.headline)
                    Spacer()
                    Button("완료") {
                        isPresented = false
                    }
                }
                .padding()

                Divider()

                List(options) { option in
                    Button {
                        onToggle(option.id)
                    } label: {
                        HStack {
                            Text(optionTitle(option))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedIDs.contains(option.id) {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canToggle(option.id))
                    .accessibilityValue(selectedIDs.contains(option.id) ? "선택됨" : "선택 안 됨")
                }
                .listStyle(.plain)

                if let onSelectAll {
                    Divider()
                    Button("전체 대원", action: onSelectAll)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .frame(minWidth: 320, idealWidth: 360, minHeight: 300, idealHeight: 420)
            .presentationCompactAdaptation(.popover)
        }
    }
}
