import CQBFirebase
import SwiftUI

struct AppContainer: View {
    @State private var store = InstructorStore(
        floorPlanFileRepository: StorageFloorPlanFileRepository(),
        sessionRepository: FirestoreSessionRepository(),
        memberRepository: FirestoreMemberRepository()
    )

    var body: some View {
        RootView()
            .environment(store)
            .environment(store.floorPlanDraft)
    }
}
