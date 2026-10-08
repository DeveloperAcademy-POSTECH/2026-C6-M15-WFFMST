import SwiftUI

struct FloorPlanListView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Text("등록된 도면 \(store.floorPlans.count)개")
            ActionButton("도면 추가", action: store.openFloorPlanCreation)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

