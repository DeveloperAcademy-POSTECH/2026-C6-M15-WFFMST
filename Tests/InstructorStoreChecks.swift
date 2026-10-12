import Foundation

// 서버 없이 화면 흐름과 선택 불변식을 검증한다. 실행: bash scripts/check-instructor-store.sh
@main
struct InstructorStoreChecks {
    @MainActor
    static func main() {
        let seedPlan = DemoFloorPlan(
            id: "seed-plan",
            name: "테스트 도면",
            fileName: "test-floor-plan.png",
            referenceDistance: 15
        )
        let store = InstructorStore(floorPlans: [seedPlan])
        expect(store.phase == .home, "홈에서 시작")
        store.startTraining()
        expect(store.phase == .home, "준비 화면을 건너뛴 훈련 시작 차단")

        store.openFloorPlanList()
        store.openFloorPlanCreation()
        store.floorPlanDraft.setName(" 취소할 도면 ")
        store.goBack()
        expect(store.phase == .floorPlanList && store.floorPlanDraft.name.isEmpty, "등록 취소 후 목록 복귀 및 draft 초기화")
        let savedPlanID = store.floorPlans.first!.id
        let savedPlanReference = store.floorPlans.first!.reference
        store.goBack()
        expect(store.phase == .home, "도면 목록 뒤로 → 홈")

        store.openSessionCreation()
        store.selectFloorPlan(savedPlanID)
        store.setTrainingName("  ")
        store.createSession()
        expect(store.phase == .sessionCreation, "공백 훈련명으로 세션 생성 차단")
        store.setTrainingName("테스트 훈련")
        store.createSession()
        expect(store.currentSession?.floorPlan == savedPlanReference, "선택 도면 참조로 세션 생성")
        store.loadReadinessSample(.empty)
        store.startTraining()
        expect(store.phase == .teamReadiness && !store.canRequestTrainingStart, "준비 완료자 0명 시작 차단")
        store.loadReadinessSample(.partial)
        store.startTraining()
        expect(store.phase == .teamReadiness, "미준비자 있을 때 시작 차단")
        expect(store.canRequestTrainingStart && store.requiresUnreadyExclusionConfirmation, "준비 완료 대원이 있으면 일괄 제외 후 시작 가능")
        store.startTrainingExcludingUnreadyParticipants()
        expect(store.phase == .trainingInProgress && store.participants.count == 3, "미준비자 일괄 제외 후 훈련 시작")
        expect(store.participants.allSatisfy(\.isReady), "훈련 참가자는 모두 준비 완료")

        store.finishTraining()
        store.finishAAR()
        store.returnHome()
        store.openSessionCreation()
        store.selectFloorPlan(savedPlanID)
        store.setTrainingName("테스트 훈련")
        store.createSession()
        store.goBack()
        expect(store.phase == .sessionCreation && store.trainingName == "테스트 훈련", "뒤로 이동 시 작성한 입력 유지")
        expect(store.selectedFloorPlanID == savedPlanID && store.participants.isEmpty, "선택 도면 유지, 이전 샘플 참가자 초기화")

        store.createSession()
        let firstID = store.participants[0].id
        store.startTraining()
        expect(store.phase == .trainingInProgress, "전원 준비 → 훈련")
        store.goBack()
        expect(store.phase == .trainingInProgress, "훈련 중 뒤로 차단")
        store.finishTraining()
        expect(store.phase == .aar && store.aarMode == .movement, "종료 → AAR 동선")
        expect(store.selectedParticipants.count == 6, "동선 전체 선택")
        store.setPlaybackPosition(420)
        store.changeAARMode(to: .video)
        expect(store.aarMode == .movement && store.selectedParticipants.count == 6, "5명 이상이면 영상 전환 차단")
        expect(store.aarNotice != nil && store.playbackPosition == 420, "영상 제한 안내, 재생 위치 유지")
        let fifthID = store.participants[4].id
        let sixthID = store.participants[5].id
        store.toggleParticipantSelection(fifthID)
        store.toggleParticipantSelection(sixthID)
        store.changeAARMode(to: .video)
        expect(store.aarMode == .video && store.selectedParticipants.count == 4, "4명 이하이면 선택을 유지해 영상 전환")
        store.toggleParticipantSelection(fifthID)
        expect(store.selectedParticipants.count == 4 && !store.isParticipantSelected(fifthID), "다섯 번째 영상 선택 차단")
        store.selectAllParticipants()
        expect(store.selectedParticipants.count == 4, "전체 선택으로 영상 제한 우회 차단")
        store.toggleParticipantSelection(firstID)
        store.toggleParticipantSelection(fifthID)
        expect(store.isParticipantSelected(fifthID), "해제 후 다른 대원 선택")
        let selectedIDs = store.selectedParticipantIDs
        store.changeAARMode(to: .movement)
        expect(store.selectedParticipantIDs == selectedIDs, "영상에서 동선으로 선택 유지")
        store.changeAARMode(to: .video)
        expect(store.selectedParticipantIDs == selectedIDs, "동선에서 영상으로 선택 유지")
        for id in selectedIDs { store.toggleParticipantSelection(id) }
        expect(store.selectedParticipants.isEmpty, "선택 없음 상태 지원")
        store.setPlaybackPosition(.nan)
        expect(store.playbackPosition == 420, "유효하지 않은 재생 위치 무시")
        store.setPlaybackPosition(-10)
        expect(store.playbackPosition == 0, "재생 위치 하한")
        store.setPlaybackPosition(10000)
        expect(store.playbackPosition == store.playbackDuration, "재생 위치 상한")
        store.finishAAR()
        expect(store.phase == .aarCompleted, "복기 종료 화면")
        store.returnHome()
        expect(store.phase == .home && store.participants.isEmpty && store.selectedParticipantIDs.isEmpty, "처음으로 → 세션 상태 초기화")
        expect(store.floorPlans.contains { $0.id == savedPlanID }, "홈 복귀 시 기존 도면 유지")

        let emptyStore = InstructorStore(floorPlans: [])
        emptyStore.openSessionCreation()
        emptyStore.createSession()
        expect(!emptyStore.canCreateSession && emptyStore.phase == .home, "도면 없음 세션 생성 진입 차단")

        checkFloorPlanGeometry()
        print("PASS: InstructorStore 화면 흐름, 입력 검증, 선택 제한, 초기화")
    }

    static func checkFloorPlanGeometry() {
        let base = LocalObstacleGrid(
            columns: 10,
            rows: 10,
            cellSizePixels: 10,
            blocked: [UInt8](repeating: 0, count: 100)
        )
        let selection = [
            LocalPlanPoint(x: 0.2, y: 0.2),
            LocalPlanPoint(x: 0.8, y: 0.2),
            LocalPlanPoint(x: 0.8, y: 0.8),
            LocalPlanPoint(x: 0.2, y: 0.8)
        ]
        let innerOpen = [
            LocalPlanPoint(x: 0.4, y: 0.4),
            LocalPlanPoint(x: 0.6, y: 0.4),
            LocalPlanPoint(x: 0.6, y: 0.6),
            LocalPlanPoint(x: 0.4, y: 0.6)
        ]
        let outline = [
            LocalPlanPoint(x: 0.1, y: 0.1),
            LocalPlanPoint(x: 0.9, y: 0.1),
            LocalPlanPoint(x: 0.9, y: 0.9),
            LocalPlanPoint(x: 0.1, y: 0.9)
        ]

        do {
            let resolved = try LocalFloorPlanGeometry.resolve(
                base: base,
                width: 100,
                height: 100,
                edits: [
                    .region(LocalEditRegion(mode: .block, points: selection)),
                    .region(LocalEditRegion(mode: .open, points: innerOpen))
                ],
                outline: outline
            )
            expect(resolved.blocked[3 * 10 + 3] == 1, "다각형 추가 영역은 장애물로 반영")
            expect(resolved.blocked[5 * 10 + 5] == 0, "나중에 적용한 다각형 삭제 영역은 통과 가능")
            expect(resolved.blocked[0] == 1, "외곽 밖은 편집 결과와 무관하게 장애물 처리")
            expect(resolved.blocked[1 * 10 + 1] == 0, "외곽 안의 편집하지 않은 영역은 유지")
        } catch {
            preconditionFailure("도면 편집 격자 검증 실패: \(error)")
        }
    }

    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }
}
