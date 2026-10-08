import SwiftUI

struct FloorPlanCreateView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            TextField("도면 이름", text: Binding(get: { store.floorPlanDraftName }, set: store.setFloorPlanDraftName))
            ActionButton("샘플 도면 사용", action: store.useSampleFloorPlan)
            ActionButton("도면 저장", action: store.saveFloorPlan).disabled(!store.canSaveFloorPlan)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

