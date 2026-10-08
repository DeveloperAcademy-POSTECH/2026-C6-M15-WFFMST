import Foundation

// 서버 없이 화면 흐름과 선택 불변식을 검증한다. 실행: bash scripts/check-instructor-store.sh
@main
struct InstructorStoreChecks {
    @MainActor
    static func main() {
        let store = InstructorStore()
        expect(store.phase == .home, "홈에서 시작")
        store.startTraining()
        expect(store.phase == .home, "준비 화면을 건너뛴 훈련 시작 차단")

        store.openFloorPlanList()
        store.openFloorPlanCreation()
        store.setFloorPlanDraftName("   ")
        store.useSampleFloorPlan()
        expect(!store.canSaveFloorPlan, "공백 이름 저장 차단")
        store.setFloorPlanDraftName(" 테스트 도면 ")
        store.saveFloorPlan()
        expect(store.phase == .floorPlanList && store.floorPlans.last?.name == "테스트 도면", "메모리 저장 후 목록 복귀")
        let savedPlanID = store.floorPlans.last!.id
        store.goBack()
        expect(store.phase == .home, "도면 목록 뒤로 → 홈")

        store.openSessionCreation()
        store.selectFloorPlan(savedPlanID)
        store.setTrainingName("  ")
        store.createSession()
        expect(store.phase == .sessionCreation, "공백 훈련명으로 세션 생성 차단")
        store.setTrainingName("테스트 훈련")
        store.createSession()
        store.loadReadinessSample(.empty)
        store.startTraining()
        expect(store.phase == .teamReadiness && !store.canStartTraining, "0명 시작 차단")
        store.loadReadinessSample(.partial)
        store.startTraining()
        expect(store.phase == .teamReadiness, "미준비자 있을 때 시작 차단")
        let firstID = store.participants[0].id
        let secondID = store.participants[1].id
        store.excludeParticipant(firstID)
        expect(store.participants.first?.id == secondID && store.participants.first?.number == 2, "제외 후 대원 식별자/번호 유지")
        store.goBack()
        expect(store.phase == .sessionCreation && store.trainingName == "테스트 훈련", "뒤로 이동 시 작성한 입력 유지")
        expect(store.selectedFloorPlanID == savedPlanID && store.participants.isEmpty, "선택 도면 유지, 이전 샘플 참가자 초기화")

        store.createSession()
        store.startTraining()
        expect(store.phase == .trainingInProgress, "전원 준비 → 훈련")
        store.goBack()
        expect(store.phase == .trainingInProgress, "훈련 중 뒤로 차단")
        store.finishTraining()
        expect(store.phase == .aar && store.aarMode == .movement, "종료 → AAR 동선")
        expect(store.selectedParticipants.count == 6, "동선 전체 선택")
        store.setPlaybackPosition(420)
        store.changeAARMode(to: .video)
        expect(store.selectedParticipants.count == 4 && store.playbackPosition == 420, "영상 4명 제한, 재생 위치 유지")
        let fifthID = store.participants[4].id
        store.toggleParticipantSelection(fifthID)
        expect(store.selectedParticipants.count == 4 && !store.isParticipantSelected(fifthID), "다섯 번째 영상 선택 차단")
        store.selectAllParticipants()
        expect(store.selectedParticipants.count == 4, "전체 선택으로 영상 제한 우회 차단")
        store.toggleParticipantSelection(firstID)
        store.toggleParticipantSelection(fifthID)
        expect(store.isParticipantSelected(fifthID), "해제 후 다른 대원 선택")
        let videoIDs = store.selectedParticipantIDs
        store.changeAARMode(to: .movement)
        expect(store.selectedParticipants.count == 6, "모드 전환 후 동선 선택 복원")
        store.changeAARMode(to: .video)
        expect(store.selectedParticipantIDs == videoIDs, "모드 전환 후 영상 선택 복원")
        for id in videoIDs { store.toggleParticipantSelection(id) }
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
        expect(store.floorPlans.contains { $0.id == savedPlanID }, "홈 복귀 시 저장한 샘플 도면 유지")

        let emptyStore = InstructorStore(floorPlans: [])
        emptyStore.openSessionCreation()
        emptyStore.createSession()
        expect(!emptyStore.canCreateSession && emptyStore.phase == .sessionCreation, "도면 없음 세션 생성 차단")
        print("PASS: InstructorStore 화면 흐름, 입력 검증, 선택 제한, 초기화")
    }

    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }
}
