import CQBCore
import CQBFirebase
import SwiftUI

struct AppContainer: View {
    @State private var store: InstructorStore
    @State private var aarStore: AARStore
    @State private var demoMode = InstructorDemoMode()

    @MainActor
    init(
        floorPlanFileRepository: any FloorPlanFileRepository,
        worldMapFileRepository: any WorldMapFileRepository = StorageWorldMapFileRepository(),
        floorPlanCatalogRepository: (any FloorPlanCatalogRepository)? = nil,
        trainingHistoryRepository: (any TrainingHistoryRepository)? = nil
    ) {
        // 쇼케이스(#252): 번들에 든 세션을 일반 모드 기록에 넣고, 그 세션만 번들 파일에서 읽는다.
        let showcase = ShowcaseSession.bundled
        let sessionRepository: any SessionRepository = showcase.map {
            ShowcaseSessionRepository(showcase: $0, fallback: FirestoreSessionRepository())
        } ?? FirestoreSessionRepository()
        let memberRepository: any MemberRepository = showcase.map {
            ShowcaseMemberRepository(showcase: $0, fallback: FirestoreMemberRepository())
        } ?? FirestoreMemberRepository()
        let recordingRepository: any RecordingRepository = showcase.map {
            ShowcaseRecordingRepository(showcase: $0, fallback: FirestoreRecordingRepository())
        } ?? FirestoreRecordingRepository()
        let historyRepository: (any TrainingHistoryRepository)? = showcase.flatMap { showcase in
            trainingHistoryRepository.map { ShowcaseTrainingHistoryRepository(showcase: showcase, base: $0) }
        } ?? trainingHistoryRepository
        let soundLoader = RepositoryAARSoundCandidateLoader(repository: StorageSoundCandidateRepository())
        _store = State(initialValue: InstructorStore(
            floorPlanDraft: FloorPlanDraftStore(worldMapScanner: LocalARWorldMapScanService()),
            floorPlanFileRepository: floorPlanFileRepository,
            worldMapFileRepository: worldMapFileRepository,
            floorPlanCatalogRepository: floorPlanCatalogRepository,
            sessionRepository: sessionRepository,
            memberRepository: memberRepository,
            recordingRepository: recordingRepository,
            trainingHistoryRepository: historyRepository
        ))
        _aarStore = State(initialValue: AARStore(
            sessionRepository: sessionRepository,
            memberRepository: memberRepository,
            recordingRepository: recordingRepository,
            trackResultRepository: showcase.map {
                ShowcaseTrackResultRepository(showcase: $0, fallback: StorageTrackResultRepository())
            } ?? StorageTrackResultRepository(),
            floorPlanFileRepository: showcase.map {
                ShowcaseFloorPlanFileRepository(showcase: $0, fallback: floorPlanFileRepository)
            } ?? floorPlanFileRepository,
            videoChunkRepository: showcase.map {
                ShowcaseVideoChunkRepository(showcase: $0, fallback: StorageVideoChunkRepository())
            } ?? StorageVideoChunkRepository(),
            soundCandidateLoader: showcase.map {
                ShowcaseSoundCandidateLoader(showcase: $0, fallback: soundLoader)
            } ?? soundLoader
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
                    .task {
                        store.loadFloorPlans()
                        store.loadTrainingHistory()
                    }
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
    @State private var environment: InstructorDemoScenario.Environment

    init() {
        _environment = State(initialValue: InstructorDemoScenario.makeEnvironment())
    }

    var body: some View {
        RootView()
            .environment(environment.store)
            .environment(environment.store.floorPlanDraft)
            .environment(environment.aarStore)
            .onDisappear {
                environment.store.shutdown()
                environment.aarStore.reset()
            }
    }
}
