import CQBFirebase
import SwiftUI

struct AppContainer: View {
    @State private var store: InstructorStore
    @State private var aarStore: AARStore
    @State private var demoMode = InstructorDemoMode()

    @MainActor
    init(
        floorPlanCatalogRepository: (any FloorPlanCatalogRepository)? = nil
    ) {
        _store = State(initialValue: InstructorStore(
            floorPlanFileRepository: StorageFloorPlanFileRepository(),
            floorPlanCatalogRepository: floorPlanCatalogRepository,
            sessionRepository: FirestoreSessionRepository(),
            memberRepository: FirestoreMemberRepository(),
            recordingRepository: FirestoreRecordingRepository()
        ))
        _aarStore = State(initialValue: AARStore(
            sessionRepository: FirestoreSessionRepository(),
            memberRepository: FirestoreMemberRepository(),
            recordingRepository: FirestoreRecordingRepository(),
            trackResultRepository: StorageTrackResultRepository(),
            floorPlanFileRepository: StorageFloorPlanFileRepository(),
            videoChunkRepository: StorageVideoChunkRepository()
        ))
    }

    var body: some View {
        Group {
            if demoMode.isActive {
                InstructorDemoContainer()
                    .id(demoMode.runID)
            } else {
                RootView()
                    .environment(store)
                    .environment(store.floorPlanDraft)
                    .environment(aarStore)
                    .task { store.loadFloorPlans() }
#if DEBUG
                    .task { await openDebugAARIfRequested() }
#endif
            }
        }
        .environment(demoMode)
    }

#if DEBUG
    /// 스킴 환경 변수 `CQB_AAR_SESSION_ID`가 있으면 그 세션으로 AAR을 바로 연다 (에뮬레이터 시험 데이터 확인용).
    private func openDebugAARIfRequested() async {
        guard let value = ProcessInfo.processInfo.environment["CQB_AAR_SESSION_ID"],
              let sessionID = UUID(uuidString: value),
              let snapshot = await aarStore.debugSnapshot(sessionID: sessionID) else { return }
        store.openAARForDebug(session: snapshot.session, members: snapshot.members)
    }
#endif
}

@MainActor
private struct InstructorDemoContainer: View {
    @State private var store = InstructorDemoScenario.makeStore()
    @State private var aarStore = AARStore()

    var body: some View {
        RootView()
            .environment(store)
            .environment(store.floorPlanDraft)
            .environment(aarStore)
    }
}
