import CQBDesignSystem
import SwiftUI

struct SelectionFieldLabel: View {
    let text: String
    var color: Color?
    var isPlaceholder = false
    var isExpanded = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .foregroundStyle(isPlaceholder ? DSColor.darkGreen : DSColor.white)
                .lineLimit(1)

            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DSColor.darkGreen)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(.easeOut(duration: 0.12), value: isExpanded)
                .accessibilityHidden(true)
        }
        .font(DSTypography.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DSColor.area1)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(DSColor.area3, lineWidth: 1)
        }
        .contentShape(.rect)
    }
}

struct SelectionDropdown<Label: View, Content: View>: View {
    @Environment(\.instructorDropdownContext) private var context
    @State private var dropdownID = UUID()
    @State private var isLocallyExpanded = false
    @State private var keepsRaisedLayer = false

    let isEnabled: Bool
    let label: (Bool) -> Label
    let content: (@escaping () -> Void) -> Content

    init(
        isEnabled: Bool = true,
        @ViewBuilder label: @escaping (Bool) -> Label,
        @ViewBuilder content: @escaping (@escaping () -> Void) -> Content
    ) {
        self.isEnabled = isEnabled
        self.label = label
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    togglePresentation()
                }
            } label: {
                label(isExpanded)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { field in
                if isExpanded {
                    content(dismissImmediately)
                        .offset(y: field.size.height + 4)
                        .transition(.opacity)
                        .reportDropdownBoundsIfNeeded(
                            id: dropdownID,
                            context: context
                        )
                }
            }
        }
        .reportDropdownBoundsIfNeeded(id: dropdownID, context: context)
        .zIndex(isExpanded ? 2 : (keepsRaisedLayer ? 1 : 0))
        .onChange(of: isExpanded) { _, expanded in
            updateRaisedLayer(isExpanded: expanded)
        }
    }

    private var isExpanded: Bool {
        if let context {
            return context.contains(dropdownID)
        }
        return isLocallyExpanded
    }

    private func togglePresentation() {
        if let context {
            context.coordinator.toggle(dropdownID)
        } else {
            isLocallyExpanded.toggle()
        }
    }

    private func dismissImmediately() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            if let context {
                guard context.contains(dropdownID) else { return }
                context.coordinator.dismiss()
            } else {
                isLocallyExpanded = false
            }
        }
    }

    private func updateRaisedLayer(isExpanded: Bool) {
        if isExpanded {
            keepsRaisedLayer = true
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !self.isExpanded else { return }
            keepsRaisedLayer = false
        }
    }
}

private extension View {
    @ViewBuilder
    func reportDropdownBoundsIfNeeded(id: UUID, context: DropdownContext?) -> some View {
        if let context {
            reportDropdownBounds(id: id, in: context.coordinateSpaceName)
        } else {
            self
        }
    }
}

struct SelectionMenuList<Option: Identifiable>: View {
    let options: [Option]
    let optionTitle: (Option) -> String
    let optionColor: (Option) -> Color?
    let isSelected: (Option.ID) -> Bool
    let canSelect: (Option.ID) -> Bool
    let onSelect: (Option.ID) -> Void
    var footerTitle: String?
    var onFooterSelect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                selectionRow(option)

                if index < options.count - 1 || footerTitle != nil {
                    menuDivider
                }
            }

            if let footerTitle, let onFooterSelect {
                Button(footerTitle, action: onFooterSelect)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.white)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .topLeading)
        .background(DSColor.area3)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(DSColor.black, lineWidth: 1)
        }
    }

    private func selectionRow(_ option: Option) -> some View {
        Button {
            onSelect(option.id)
        } label: {
            HStack(spacing: 8) {
                Text(optionTitle(option))
                    .lineLimit(1)

                if let color = optionColor(option) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }

                Spacer(minLength: 8)

                if isSelected(option.id) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .accessibilityHidden(true)
                }
            }
            .font(DSTypography.body)
            .foregroundStyle(DSColor.white)
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canSelect(option.id))
        .opacity(canSelect(option.id) ? 1 : 0.45)
        .accessibilityValue(isSelected(option.id) ? "선택됨" : "선택 안 됨")
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(DSColor.white)
            .frame(height: 1)
            .padding(.vertical, 11.5)
            .accessibilityHidden(true)
    }
}
