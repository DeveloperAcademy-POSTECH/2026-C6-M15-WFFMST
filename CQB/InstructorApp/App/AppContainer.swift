import CQBFirebase
import SwiftUI

struct AppContainer: View {
    @State private var store = InstructorStore(
        floorPlanFileRepository: StorageFloorPlanFileRepository(),
        sessionRepository: FirestoreSessionRepository(),
        memberRepository: FirestoreMemberRepository()
    )
    @State private var aarStore = AARStore(
        sessionRepository: FirestoreSessionRepository(),
        memberRepository: FirestoreMemberRepository(),
        recordingRepository: FirestoreRecordingRepository(),
        trackResultRepository: StorageTrackResultRepository(),
        floorPlanFileRepository: StorageFloorPlanFileRepository(),
        videoChunkRepository: StorageVideoChunkRepository()
    )

    var body: some View {
        RootView()
            .environment(store)
            .environment(store.floorPlanDraft)
            .environment(aarStore)
#if DEBUG
            .task { await openDebugAARIfRequested() }
#endif
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
