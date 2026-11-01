import CQBCore
import Foundation

// 서버 없이 세션 생성·구독 생명주기와 기존 화면 흐름 불변식을 검증한다.
// 실행: bash scripts/check-instructor-store.sh
@main
struct InstructorStoreChecks {
    @MainActor
    static func main() async {
        await checkSessionCreationAndMemberObservation()
        await checkPinRetryLimit()
        await checkNonCollisionFailureAndRetry()
        await checkSessionCreationInputLock()
        await checkReadinessStartGuards()
        await checkEndingGuardsAndFailureRecovery()
        await TrainingLifecycleChecks.run()
        checkTrainingAndAARFlow()
        checkFloorPlanCatalogRestoration()
        checkFloorPlanFlow()
        checkFloorPlanGeometry()
        print("PASS: InstructorStore 세션 생성·입력 잠금, 구독 오류·재연결 시작 차단, 종료 경합·실패 복구, 화면 흐름")
    }

    @MainActor
    static func checkFloorPlanCatalogRestoration() {
        let first = InstructorFloorPlan(
            id: "first-plan",
            name: "첫 번째 도면",
            fileName: "first.png",
            referenceDistance: 10,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let second = InstructorFloorPlan(
            id: "second-plan",
            name: "두 번째 도면",
            fileName: "second.png",
            referenceDistance: 20,
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let catalog = DemoFloorPlanCatalogRepository(floorPlans: [first, second])
        let store = InstructorStore(floorPlanCatalogRepository: catalog)

        expect(!store.canOpenSessionCreation, "복원 전 세션 생성 차단")
        store.loadFloorPlans()
        expect(store.floorPlanCatalogState == .loaded, "도면 카탈로그 복원 완료")
        expect(store.floorPlans.map(\.id) == [first.id, second.id], "저장된 도면 목록 복원")
        expect(store.selectedFloorPlanID == first.id && store.canOpenSessionCreation,
               "복원 후 기본 도면 선택·세션 생성 허용")

        let failingCatalog = DemoFloorPlanCatalogRepository(floorPlans: [first])
        failingCatalog.fetchError = CheckError.disconnected
        let failingStore = InstructorStore(floorPlanCatalogRepository: failingCatalog)
        failingStore.loadFloorPlans()
        expect(failingStore.floorPlanCatalogError != nil && failingStore.floorPlans.isEmpty,
               "복원 실패를 빈 목록 성공으로 처리하지 않음")
        failingCatalog.fetchError = nil
        failingStore.retryFloorPlanCatalogLoad()
        expect(failingStore.floorPlanCatalogState == .loaded && failingStore.floorPlans == [first],
               "복원 재시도 성공")
    }

    @MainActor
    static func checkSessionCreationAndMemberObservation() async {
        let plan = makePlan()
        let sessionRepository = SessionRepositorySpy(creationOutcomes: [.pinTaken, .pinTaken, nil])
        let firstStream = MemberStream()
        let secondStream = MemberStream()
        let memberRepository = MemberRepositorySpy(streams: [firstStream.stream, secondStream.stream])
        let pins = PinSequence(["000001", "004200", "987654"])
        let store = InstructorStore(
            floorPlans: [plan],
            sessionRepository: sessionRepository,
            memberRepository: memberRepository,
            pinGenerator: pins.next
        )

        store.openSessionCreation()
        store.setTrainingName("  실내 진입 훈련  ")
        store.createSession()
        store.createSession()
        expect(store.isCreatingSession, "세션 생성 중 상태 표시")
        expect(store.phase == .sessionCreation, "저장 성공 전 화면 이동 차단")

        await waitUntil("세션 생성 성공") { store.phase == .teamReadiness }
        let created = sessionRepository.createdSessions
        expect(created.count == 3, "PIN 충돌 두 번 뒤 세 번째 생성")
        expect(created.map(\.pin) == ["000001", "004200", "987654"], "충돌마다 새 PIN 생성")
        expect(created.allSatisfy { $0.pin.count == 6 && $0.pin.allSatisfy(\.isNumber) }, "고정 길이 숫자 PIN")
        expect(created.last?.name == "실내 진입 훈련", "훈련명 공백 제거")
        expect(created.last?.status == .waiting, "waiting 상태로 생성")
        expect(created.last?.floorPlan == plan.reference, "선택 도면 참조로 생성")
        expect(store.currentSession?.pin == "987654", "저장 성공한 PIN 보관")
        expect(memberRepository.observationCount == 1, "생성 직후 한 번만 구독")

        firstStream.continuation.yield([])
        await waitUntil("빈 스냅샷 반영") { store.memberConnectionState == .connected }
        expect(store.participants.isEmpty && !store.canRequestTrainingStart, "빈 스냅샷은 시작 불가")

        let sessionID = store.currentSession!.id
        let first = Member(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            sessionID: sessionID,
            name: "매버릭",
            isReady: false,
            lastActiveAt: .now
        )
        let second = Member(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sessionID: sessionID,
            name: "유키",
            isReady: true,
            lastActiveAt: .now
        )
        firstStream.continuation.yield([first, second])
        await waitUntil("참가자 스냅샷 반영") { store.participants.count == 2 }
        expect(store.participants.map(\.name) == ["유키", "매버릭"], "결정적인 순서로 실제 이름 표시")
        expect(store.readyCount == 1 && store.unreadyCount == 1, "준비 인원 최신 계산")
        expect(store.canRequestTrainingStart && !store.canStartTraining, "일부 준비 시작 조건")

        firstStream.continuation.yield([first, Member(
            id: second.id,
            sessionID: sessionID,
            name: second.name,
            isReady: false,
            lastActiveAt: .now
        )])
        await waitUntil("준비 상태 변경 반영") { store.readyCount == 0 }
        expect(!store.canRequestTrainingStart, "최신 스냅샷에서 준비자 없으면 시작 차단")

        firstStream.continuation.finish(throwing: CheckError.disconnected)
        await waitUntil("구독 오류 표시") { store.memberObservationError != nil }
        store.retryMemberObservation()
        await waitUntil("재연결 시작") { memberRepository.observationCount == 2 }
        store.retryMemberObservation()
        expect(memberRepository.observationCount == 2, "재연결 중 중복 구독 차단")
        secondStream.continuation.yield([second])
        await waitUntil("재연결 스냅샷 복구") {
            store.participants.count == 1 && store.participants[0].isReady
        }

        store.goBack()
        await waitUntil("세션 종료 후 생성 화면 복귀") { store.phase == .sessionCreation }
        expect(sessionRepository.statusUpdates.count == 1, "뒤로 가기에서 세션 종료 한 번 요청")
        expect(sessionRepository.statusUpdates.first?.1 == .ended, "뒤로 가기에서 ended 전환")
        expect(store.currentSession == nil && store.participants.isEmpty, "종료 후 세션과 참가자 초기화")
        secondStream.continuation.yield([first, second])
        try? await Task.sleep(nanoseconds: 20_000_000)
        expect(store.participants.isEmpty, "화면 이탈 뒤 참가자 갱신 중단")
    }

    @MainActor
    static func checkPinRetryLimit() async {
        let plan = makePlan()
        let repository = SessionRepositorySpy(
            creationOutcomes: Array(repeating: RepositoryError.pinTaken, count: 5)
        )
        let pins = PinSequence(["000000", "000001", "000002", "000003", "000004"])
        let store = InstructorStore(
            floorPlans: [plan],
            sessionRepository: repository,
            pinGenerator: pins.next
        )
        store.openSessionCreation()
        store.createSession()
        await waitUntil("PIN 재시도 한도 실패") { store.sessionCreationError != nil }
        expect(repository.createdSessions.count == 5, "PIN 충돌은 최대 5회 시도")
        expect(store.phase == .sessionCreation && store.currentSession == nil, "생성 실패 시 현재 화면 유지")
        expect(store.canCreateSession, "실패 후 재시도 가능")
    }

    @MainActor
    static func checkNonCollisionFailureAndRetry() async {
        let repository = SessionRepositorySpy(creationOutcomes: [.notFound, nil])
        let stream = MemberStream()
        let store = InstructorStore(
            floorPlans: [makePlan()], sessionRepository: repository,
            memberRepository: MemberRepositorySpy(streams: [stream.stream])
        )
        store.openSessionCreation()
        store.createSession()
        await waitUntil("충돌 외 생성 실패") { store.sessionCreationError != nil }
        expect(repository.createdSessions.count == 1, "충돌 외 오류는 자동 재시도하지 않음")
        expect(store.phase == .sessionCreation && store.canCreateSession, "생성 실패 후 수동 재시도 허용")
        store.createSession()
        await waitUntil("수동 재시도 성공") { store.phase == .teamReadiness }
        expect(repository.createdSessions.count == 2 && store.sessionCreationError == nil, "재시도 성공 후 오류 해제")
        store.goBack()
        await waitUntil("검증 세션 종료") { store.phase == .sessionCreation }
    }

    @MainActor
    static func checkSessionCreationInputLock() async {
        for failsFirst in [false, true] {
            let firstPlan = makePlan()
            let secondPlan = InstructorFloorPlan(
                id: "second-plan", name: "다른 도면", fileName: "second.png", referenceDistance: 20
            )
            let repository = SessionRepositorySpy(creationOutcomes: [], suspendsCreations: true)
            let stream = MemberStream()
            let store = InstructorStore(
                floorPlans: [firstPlan, secondPlan], sessionRepository: repository,
                memberRepository: MemberRepositorySpy(streams: [stream.stream])
            )
            store.openSessionCreation()
            store.setTrainingName("첫 훈련")
            store.createSession()
            await waitUntil("생성 응답 대기") { repository.hasPendingCreation }

            // UI 잠금을 우회하는 늦은 콜백과 직접 호출도 제출한 값을 바꾸지 못해야 한다.
            store.setTrainingName("다른 훈련")
            store.selectFloorPlan(secondPlan.id)
            store.selectFloorPlan(nil)
            expect(store.trainingName == "첫 훈련", "생성 중 훈련명 변경 차단")
            expect(store.selectedFloorPlan?.reference == firstPlan.reference, "생성 중 도면 변경·해제 차단")
            store.createSession()
            store.goBack()
            expect(repository.createdSessions.count == 1 && store.phase == .sessionCreation,
                   "생성 대기 중 중복 요청·뒤로가기 차단 유지")

            if failsFirst {
                repository.completeCreation(error: CheckError.disconnected)
                await waitUntil("생성 실패 후 잠금 해제") { !store.isCreatingSession }
                expect(store.sessionCreationError != nil && store.currentSession == nil,
                       "생성 실패는 제출 전 화면에서 오류 표시")
                store.setTrainingName("다른 훈련")
                store.selectFloorPlan(secondPlan.id)
                expect(store.trainingName == "다른 훈련" && store.selectedFloorPlan?.reference == secondPlan.reference,
                       "생성 실패 후 훈련명·도면 수정 허용")
                store.createSession()
                await waitUntil("수정한 값으로 재시도") { repository.hasPendingCreation }
                store.setTrainingName("첫 훈련")
                store.selectFloorPlan(firstPlan.id)
                expect(store.trainingName == "다른 훈련" && store.selectedFloorPlan?.reference == secondPlan.reference,
                       "재시도 중에도 입력 잠금")
            }

            repository.completeCreation()
            await waitUntil("입력 잠금 검사 생성 성공") { store.phase == .teamReadiness }
            let expectedPlan = failsFirst ? secondPlan : firstPlan
            let expectedName = failsFirst ? "다른 훈련" : "첫 훈련"
            expect(!store.isCreatingSession && store.sessionCreationError == nil, "성공 후 생성 상태·오류 해제")
            expect(repository.createdSessions.last?.floorPlan == expectedPlan.reference,
                   "Repository에 제출한 도면 유지")
            expect(store.currentSession?.floorPlan == store.selectedFloorPlan?.reference,
                   "성공한 서버 세션과 화면 선택 도면 일치")
            expect(store.currentSession?.name == expectedName && store.trainingName == expectedName,
                   "성공한 서버 세션과 화면 훈련명 일치")
            store.goBack()
            await waitUntil("입력 잠금 검사 세션 종료") { store.phase == .sessionCreation }
        }
    }

    @MainActor
    static func checkReadinessStartGuards() async {
        // 전원 준비·일부 준비 모두에서 두 시작 메서드가 우회 경로가 되지 않아야 한다.
        for allReady in [true, false] {
            let first = MemberStream()
            let recovered = MemberStream()
            let members = MemberRepositorySpy(streams: [first.stream, recovered.stream])
            let store = InstructorStore(
                floorPlans: [makePlan()], sessionRepository: SessionRepositorySpy(creationOutcomes: []),
                memberRepository: members
            )
            store.openSessionCreation()
            store.createSession()
            await waitUntil("최초 구독 시작") { members.observationCount == 1 }
            expect(store.memberConnectionState == .connecting, "첫 스냅샷 전 연결 중")
            expectStartBlocked(store, "최초 스냅샷 전")
            let snapshot = makeMembers(sessionID: store.currentSession!.id, allReady: allReady)
            first.continuation.yield(snapshot)
            await waitUntil("준비 스냅샷") { store.memberConnectionState == .connected }
            expect(store.canRequestTrainingStart, "준비자가 있으면 시작 요청 허용")

            first.continuation.finish(throwing: CheckError.disconnected)
            await waitUntil("구독 오류") { store.memberConnectionState == .failed }
            expect(store.readyCount > 0 && store.canRetryMemberObservation, "이전 목록은 표시하되 재연결 필요")
            expectStartBlocked(store, "구독 오류 후")

            store.retryMemberObservation()
            store.retryMemberObservation()
            await waitUntil("재연결 구독") { members.observationCount == 2 }
            expect(store.memberConnectionState == .connecting && !store.canRetryMemberObservation, "중복 재연결 차단")
            expectStartBlocked(store, "재연결 첫 스냅샷 전")
            recovered.continuation.yield([])
            await waitUntil("빈 현재 목록으로 복구") { store.memberConnectionState == .connected }
            expect(store.participants.isEmpty, "재연결 후 이전 목록을 최신 빈 스냅샷으로 교체")
            expectStartBlocked(store, "빈 목록 복구 후")
            recovered.continuation.yield(snapshot)
            await waitUntil("준비 목록 복구") { store.canRequestTrainingStart }
            if allReady { store.startTraining() }
            else { store.startTrainingExcludingUnreadyParticipants() }
            await waitUntil("복구된 현재 스냅샷으로 서버 시작 성공") { store.phase == .trainingInProgress }
            await waitUntil("시작 후 구독 취소") { recovered.terminationCount == 1 }
            store.returnHome()
        }

        let stream = MemberStream()
        let store = InstructorStore(
            floorPlans: [makePlan()], sessionRepository: SessionRepositorySpy(creationOutcomes: []),
            memberRepository: MemberRepositorySpy(streams: [stream.stream])
        )
        store.openSessionCreation()
        store.createSession()
        await waitUntil("정상 종료 검사 준비") { store.phase == .teamReadiness }
        stream.continuation.finish()
        await waitUntil("예기치 않은 스트림 정상 종료") { store.memberConnectionState == .failed }
        expect(store.canRetryMemberObservation, "정상 종료된 스트림도 재연결 허용")
        store.goBack()
        await waitUntil("정상 종료 검사 정리") { store.phase == .sessionCreation }
    }

    @MainActor
    static func checkEndingGuardsAndFailureRecovery() async {
        for failsFirst in [false, true] {
            let repository = SessionRepositorySpy(creationOutcomes: [], suspendsStatusUpdates: true)
            let first = MemberStream()
            let recovered = MemberStream()
            let members = MemberRepositorySpy(streams: [first.stream, recovered.stream])
            let store = InstructorStore(
                floorPlans: [makePlan()], sessionRepository: repository, memberRepository: members
            )
            store.openSessionCreation()
            store.createSession()
            await waitUntil("종료 검사 세션 생성") { store.phase == .teamReadiness }
            let sessionID = store.currentSession!.id
            first.continuation.yield(makeMembers(sessionID: sessionID, allReady: true))
            await waitUntil("종료 전 준비 완료") { store.canStartTraining }
            store.goBack()
            await waitUntil("서버 종료 대기") { repository.hasPendingStatusUpdate }
            expect(store.isEndingSession && !store.canGoBack, "종료 중 뒤로가기 비활성화")
            expectStartBlocked(store, "서버 종료 대기 중")
            store.goBack()
            store.retryMemberObservation()
            expect(store.currentSession?.id == sessionID && store.phase == .teamReadiness, "중복 뒤로가기로 조기 초기화 금지")
            expect(repository.statusUpdates.count == 1 && members.observationCount == 1, "종료·재연결 중복 요청 없음")
            await waitUntil("종료 중 구독 해제") { first.terminationCount == 1 }

            if failsFirst {
                repository.completeStatusUpdate(error: CheckError.disconnected)
                await waitUntil("종료 실패 뒤 재구독") { members.observationCount == 2 }
                expect(!store.isEndingSession && store.sessionEndError != nil, "종료 실패 복구와 오류 표시")
                expect(store.memberConnectionState == .connecting, "종료 실패 후 새 스냅샷 대기")
                expectStartBlocked(store, "종료 실패 후 재연결 중")
                recovered.continuation.yield(makeMembers(sessionID: sessionID, allReady: true))
                await waitUntil("종료 실패 후 준비 복구") { store.canStartTraining }
                store.goBack()
                await waitUntil("종료 재시도") { repository.hasPendingStatusUpdate }
                expect(repository.statusUpdates.count == 2, "종료 실패 후 한 번만 재시도")
            }
            repository.completeStatusUpdate()
            await waitUntil("종료 성공 후 화면 복귀") { store.phase == .sessionCreation }
            expect(!store.isEndingSession && store.currentSession == nil && store.participants.isEmpty, "종료 성공 후 상태 완전 초기화")
            first.continuation.yield(makeMembers(sessionID: sessionID, allReady: true))
            recovered.continuation.yield(makeMembers(sessionID: sessionID, allReady: true))
            try? await Task.sleep(for: .milliseconds(20))
            expect(store.participants.isEmpty && store.memberConnectionState == .idle, "종료 뒤 늦은 스냅샷 무시")
        }
    }

    @MainActor
    static func expectStartBlocked(_ store: InstructorStore, _ context: String) {
        let participants = store.participants
        expect(!store.canStartTraining && !store.canRequestTrainingStart, "\(context): 두 시작 조건 차단")
        store.startTraining()
        store.startTrainingExcludingUnreadyParticipants()
        expect(store.phase == .teamReadiness && store.participants == participants, "\(context): 직접 호출도 전환·참가자 제거 금지")
    }

    static func makeMembers(sessionID: UUID, allReady: Bool) -> [Member] {
        [
            Member(id: UUID(), sessionID: sessionID, name: "준비 대원", isReady: true, lastActiveAt: .now),
            Member(id: UUID(), sessionID: sessionID, name: "다른 대원", isReady: allReady, lastActiveAt: .now),
        ]
    }

    @MainActor
    static func checkTrainingAndAARFlow() {
        let plan = makePlan()
        var participants = InstructorPreviewFixture.participants
        for index in participants.indices { participants[index].isReady = index < 3 }
        let store = InstructorPreviewFixture.store(
            floorPlan: plan, participants: participants.filter(\.isReady), phase: .aar
        )
        expect(store.phase == .aar && store.selectedParticipants.isEmpty && store.aarScreen == .floorPlan,
               "AAR은 선택 없는 도면 화면으로 진입")
        expect(!store.canOpenAARVideoScreen, "선택 전 영상 화면 진입 차단")
        store.openAARVideoScreen()
        expect(store.aarScreen == .floorPlan, "선택 없는 직접 영상 화면 요청 차단")

        let firstID = store.participants[0].id
        let secondID = store.participants[1].id
        store.toggleParticipantSelection(firstID)
        expect(store.selectedParticipantIDs == [firstID] && store.videoSlotNumber(for: firstID) == 1,
               "첫 선택을 최신 영상 슬롯 1에 배치")
        expect(store.isParticipantMuted(firstID), "새로 선택한 영상은 기본 음소거")
        store.toggleParticipantMute(firstID)
        expect(!store.isParticipantMuted(firstID), "선택 영상 음소거 해제 상태 보존")
        store.openAARVideoScreen()
        store.toggleParticipantSelection(secondID)
        expect(store.aarScreen == .video && store.selectedParticipantIDs == [secondID, firstID],
               "영상 화면에서 최신 선택을 위로 배치")
        expect(store.videoSlotNumber(for: secondID) == 1 && store.videoSlotNumber(for: firstID) == 2,
               "선택 순서에 맞춰 영상 슬롯 번호 재할당")
        store.showAARFloorPlan()
        store.openAARVideoScreen()
        expect(store.aarScreen == .video && !store.isParticipantMuted(firstID),
               "화면 왕복에서 선택 순서와 음소거 상태 유지")
        store.setPlaybackPosition(.nan)
        expect(store.playbackPosition == 331, "유효하지 않은 재생 위치 무시")
        store.finishAAR()
        expect(store.phase == .aarCompleted && store.aarScreen == .floorPlan
                   && store.selectedParticipantIDs.isEmpty && store.unmutedParticipantIDs.isEmpty,
               "AAR 종료 시 선택·화면·음소거 상태 초기화")
        store.returnHome()
        expect(store.phase == .home && store.participants.isEmpty, "처음으로에서 세션 상태 초기화")

        let aarStore = InstructorPreviewFixture.store(floorPlan: plan, phase: .aar)
        let ids = aarStore.participants.map(\.id)
        ids.prefix(4).forEach(aarStore.toggleParticipantSelection)
        expect(aarStore.selectedParticipantIDs == Array(ids.prefix(4).reversed()),
               "최근 선택 순서로 최대 4명 배치")
        let oldestID = ids[0]
        let newestID = ids[4]
        aarStore.toggleParticipantMute(oldestID)
        aarStore.toggleParticipantSelection(newestID)
        expect(aarStore.selectedParticipantIDs == [newestID, ids[3], ids[2], ids[1]],
               "다섯 번째 선택 시 가장 오래된 대원 제거")
        expect(aarStore.videoSlotNumber(for: newestID) == 1
                   && aarStore.videoSlotNumber(for: ids[1]) == 4,
               "FIFO 이후 영상 슬롯 번호 갱신")
        expect(!aarStore.unmutedParticipantIDs.contains(oldestID),
               "FIFO로 제거된 대원의 음소거 해제 상태 삭제")

        aarStore.openAARVideoScreen()
        aarStore.toggleParticipantMute(ids[3])
        aarStore.toggleParticipantSelection(ids[3])
        expect(aarStore.selectedParticipantIDs == [newestID, ids[2], ids[1]]
                   && aarStore.videoSlotNumber(for: ids[2]) == 2,
               "중간 선택 해제 후 빈자리 없이 슬롯 번호 재할당")
        expect(!aarStore.unmutedParticipantIDs.contains(ids[3]),
               "직접 선택 해제한 대원의 음소거 해제 상태 삭제")

        aarStore.selectedParticipantIDs.forEach(aarStore.toggleParticipantSelection)
        expect(aarStore.selectedParticipantIDs.isEmpty && aarStore.aarScreen == .floorPlan,
               "영상 화면에서 마지막 대원 해제 시 도면 화면 복귀")
        aarStore.toggleParticipantMute(ids[5])
        expect(aarStore.unmutedParticipantIDs.isEmpty, "미선택 대원의 음소거 변경 무시")
        aarStore.toggleParticipantSelection("unknown")
        expect(aarStore.selectedParticipantIDs.isEmpty, "참가 명단에 없는 대원 선택 무시")

        aarStore.setPlaybackPosition(420)
        aarStore.setPlaybackPosition(-10)
        expect(aarStore.playbackPosition == 0, "재생 위치 하한")
        aarStore.setPlaybackPosition(10_000)
        expect(aarStore.playbackPosition == aarStore.playbackDuration, "재생 위치 상한")
    }

    @MainActor
    static func checkFloorPlanFlow() {
        let store = InstructorStore(floorPlans: [makePlan()])
        store.openSessionCreation()
        store.setTrainingName("  ")
        store.createSession()
        expect(store.phase == .sessionCreation && !store.canCreateSession, "공백 훈련명 세션 생성 차단")
        store.goBack()
        store.openFloorPlanList()
        store.openFloorPlanCreation()
        store.floorPlanDraft.setName(" 취소할 도면 ")
        store.goBack()
        expect(store.phase == .floorPlanList && store.floorPlanDraft.name.isEmpty, "도면 등록 취소")
        store.goBack()
        expect(store.phase == .home, "도면 목록 뒤로 → 홈")

        let emptyStore = InstructorStore(floorPlans: [])
        emptyStore.openSessionCreation()
        emptyStore.createSession()
        expect(!emptyStore.canCreateSession && emptyStore.phase == .home, "도면 없는 세션 생성 차단")
    }

    static func makePlan() -> InstructorFloorPlan {
        InstructorFloorPlan(
            id: "seed-plan",
            name: "테스트 도면",
            fileName: "test-floor-plan.png",
            referenceDistance: 15
        )
    }

    @MainActor
    static func waitUntil(_ message: String, condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        preconditionFailure("시간 내 상태 도달 실패: \(message)")
    }

    static func checkFloorPlanGeometry() {
        let base = LocalObstacleGrid(columns: 10, rows: 10, cellSizePixels: 10, blocked: [UInt8](repeating: 0, count: 100))
        let selection = [
            LocalPlanPoint(x: 0.2, y: 0.2), LocalPlanPoint(x: 0.8, y: 0.2),
            LocalPlanPoint(x: 0.8, y: 0.8), LocalPlanPoint(x: 0.2, y: 0.8)
        ]
        let innerOpen = [
            LocalPlanPoint(x: 0.4, y: 0.4), LocalPlanPoint(x: 0.6, y: 0.4),
            LocalPlanPoint(x: 0.6, y: 0.6), LocalPlanPoint(x: 0.4, y: 0.6)
        ]
        let outline = [
            LocalPlanPoint(x: 0.1, y: 0.1), LocalPlanPoint(x: 0.9, y: 0.1),
            LocalPlanPoint(x: 0.9, y: 0.9), LocalPlanPoint(x: 0.1, y: 0.9)
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
            expect(resolved.blocked[3 * 10 + 3] == 1, "다각형 추가 영역 반영")
            expect(resolved.blocked[5 * 10 + 5] == 0, "나중의 삭제 영역 반영")
            expect(resolved.blocked[0] == 1, "외곽 밖 장애물 처리")
            expect(resolved.blocked[1 * 10 + 1] == 0, "외곽 안 미편집 영역 유지")
        } catch {
            preconditionFailure("도면 편집 격자 검증 실패: \(error)")
        }
    }

    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }
}

private enum CheckError: Error {
    case disconnected
}

private final class PinSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var pins: [String]

    init(_ pins: [String]) { self.pins = pins }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return pins.isEmpty ? "999999" : pins.removeFirst()
    }
}

private final class SessionRepositorySpy: SessionRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [RepositoryError?]
    private var storedSessions: [Session] = []
    private var storedUpdates: [(UUID, SessionStatus)] = []
    private let suspendsCreations: Bool
    private var pendingCreation: CheckedContinuation<Void, Error>?
    private let suspendsStatusUpdates: Bool
    private var pendingStatusUpdate: CheckedContinuation<Void, Error>?

    init(creationOutcomes: [RepositoryError?], suspendsCreations: Bool = false, suspendsStatusUpdates: Bool = false) {
        outcomes = creationOutcomes
        self.suspendsCreations = suspendsCreations
        self.suspendsStatusUpdates = suspendsStatusUpdates
    }

    var hasPendingCreation: Bool { lock.withLock { pendingCreation != nil } }

    func completeCreation(error: Error? = nil) {
        let continuation = lock.withLock {
            let result = pendingCreation
            pendingCreation = nil
            return result
        }
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
    }

    var hasPendingStatusUpdate: Bool { lock.withLock { pendingStatusUpdate != nil } }

    func completeStatusUpdate(error: Error? = nil) {
        let continuation = lock.withLock {
            let result = pendingStatusUpdate
            pendingStatusUpdate = nil
            return result
        }
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
    }

    var createdSessions: [Session] {
        lock.lock()
        defer { lock.unlock() }
        return storedSessions
    }

    var statusUpdates: [(UUID, SessionStatus)] {
        lock.lock()
        defer { lock.unlock() }
        return storedUpdates
    }

    func createSession(_ session: Session) async throws {
        let outcome = lock.withLock {
            storedSessions.append(session)
            return outcomes.isEmpty ? nil : outcomes.removeFirst()
        }
        if suspendsCreations {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { pendingCreation = continuation }
            }
        }
        if let outcome { throw outcome }
    }

    func session(forPin pin: String) async throws -> Session { throw RepositoryError.notFound }

    func updateStatus(of session: Session, to status: SessionStatus) async throws {
        if suspendsStatusUpdates {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    storedUpdates.append((session.id, status))
                    pendingStatusUpdate = continuation
                }
            }
            return
        }
        lock.withLock {
            storedUpdates.append((session.id, status))
        }
    }

    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private final class MemberStream: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTerminationCount = 0
    var terminationCount: Int { lock.withLock { storedTerminationCount } }
    let stream: AsyncThrowingStream<[Member], Error>
    let continuation: AsyncThrowingStream<[Member], Error>.Continuation

    init() {
        var captured: AsyncThrowingStream<[Member], Error>.Continuation?
        stream = AsyncThrowingStream { captured = $0 }
        continuation = captured!
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.storedTerminationCount += 1 }
        }
    }
}

private final class MemberRepositorySpy: MemberRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [AsyncThrowingStream<[Member], Error>]
    private var storedObservationCount = 0

    init(streams: [AsyncThrowingStream<[Member], Error>]) { self.streams = streams }

    var observationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedObservationCount
    }

    func join(_ member: Member, pin: String) async throws {}
    func updateReadiness(of member: Member) async throws {}

    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        lock.lock()
        defer { lock.unlock() }
        storedObservationCount += 1
        guard !streams.isEmpty else { return AsyncThrowingStream { $0.finish() } }
        return streams.removeFirst()
    }
}
