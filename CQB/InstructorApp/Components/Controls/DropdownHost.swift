import Observation
import SwiftUI

@Observable
final class DropdownCoordinator {
    var activeID: UUID?
    @ObservationIgnored var bounds: [UUID: [CGRect]] = [:]

    func toggle(_ id: UUID) {
        activeID = activeID == id ? nil : id
    }

    func dismiss() {
        activeID = nil
    }
}

struct DropdownContext {
    let coordinator: DropdownCoordinator
    let coordinateSpaceName: UUID

    func contains(_ id: UUID) -> Bool {
        coordinator.activeID == id
    }
}

private struct DropdownContextKey: EnvironmentKey {
    static let defaultValue: DropdownContext? = nil
}

extension EnvironmentValues {
    var instructorDropdownContext: DropdownContext? {
        get { self[DropdownContextKey.self] }
        set { self[DropdownContextKey.self] = newValue }
    }
}

private struct DropdownBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: [CGRect]] = [:]

    static func reduce(value: inout [UUID: [CGRect]], nextValue: () -> [UUID: [CGRect]]) {
        for (id, bounds) in nextValue() {
            value[id, default: []].append(contentsOf: bounds)
        }
    }
}

struct DropdownHost<Content: View>: View {
    @State private var coordinator = DropdownCoordinator()
    @State private var coordinateSpaceName = UUID()

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .coordinateSpace(name: coordinateSpaceName)
            .environment(
                \.instructorDropdownContext,
                DropdownContext(
                    coordinator: coordinator,
                    coordinateSpaceName: coordinateSpaceName
                )
            )
            .onPreferenceChange(DropdownBoundsPreferenceKey.self) {
                coordinator.bounds = $0
            }
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                    .onEnded(handleTap)
            )
    }

    private func handleTap(_ value: SpatialTapGesture.Value) {
        guard let activeID = coordinator.activeID else { return }
        let activeBounds = coordinator.bounds[activeID, default: []]
        guard !activeBounds.contains(where: { $0.contains(value.location) }) else { return }

        withAnimation(.easeOut(duration: 0.12)) {
            coordinator.dismiss()
        }
    }
}

private struct DropdownBoundsReporter: ViewModifier {
    let id: UUID
    let coordinateSpaceName: UUID

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DropdownBoundsPreferenceKey.self,
                    value: [id: [proxy.frame(in: .named(coordinateSpaceName))]]
                )
            }
        }
    }
}

extension View {
    func reportDropdownBounds(id: UUID, in coordinateSpaceName: UUID) -> some View {
        modifier(
            DropdownBoundsReporter(
                id: id,
                coordinateSpaceName: coordinateSpaceName
            )
        )
    }
}
