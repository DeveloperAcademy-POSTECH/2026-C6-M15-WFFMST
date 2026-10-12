import CQBFirebase
import SwiftUI

struct AppContainer: View {
    @State private var store = InstructorStore(
        floorPlanFileRepository: StorageFloorPlanFileRepository()
    )

    var body: some View {
        RootView()
            .environment(store)
            .environment(store.floorPlanDraft)
    }
}
