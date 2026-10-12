import CQBCore
import Foundation

@MainActor
enum TrainingLifecycleChecks {
    static func run() async {
        await checkLifecycleAndRecovery()
        await checkExclusionAndCancellation()
        await checkEmptyRosterAndNormalStreamEnd()
        print("PASS: 훈련 서버 시작·종료, 서버 타이머, 기록 전원 종결, 오류·재연결·취소")
    }

    private static func checkLifecycleAndRecovery() async {
        let (store, repository, members) = await readyStore()
        let session = store.currentSession!
        store.startTraining()
        await wait("시작 쓰기 대기") { repository.hasPendingWrite }
        expect(store.phase == .teamReadiness && store.isStartingTraining, "서버 성공 전 준비 화면 유지")
        expect(store.trainingParticipants.isEmpty && !store.canGoBack && !store.canRequestTrainingStart, "시작 중 확정·뒤로·중복 시작 차단")
        store.startTrainingExcludingUnreadyParticipants()
        store.goBack()
        store.retryMemberObservation()
        expect(repository.writes == [.running] && repository.memberCount == 1, "시작 중 중복 쓰기·구독 없음")
        repository.completeWrite(error: Failure.disconnected)
        await wait("시작 실패 복구") { repository.memberCount == 2 }
        expect(store.phase == .teamReadiness && store.trainingActionError != nil && !store.canStartTraining, "시작 실패 후 새 준비 스냅샷 필요")
        repository.members[1].send(members)
        await wait("시작 실패 후 준비 복구") { store.canStartTraining }
        store.startTraining()
        await wait("시작 재시도") { repository.hasPendingWrite }
        repository.completeWrite()
        await wait("서버 시작 성공") { store.phase == .trainingInProgress && repository.sessionCount == 1 }
        expect(store.trainingParticipants.map(\.id) == store.participants.map(\.id), "시작 성공 시 참가 명단 확정")
        expect(store.trainingElapsed(at: .now) == nil, "클라이언트 버튼 시각으로 타이머를 채우지 않음")

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        repository.sessions[0].send(updated(session, status: .waiting))
        repository.sessions[0].send(updated(session, status: .running, start: start))
        await wait("서버 시작 시각 수신") { store.currentSession?.startedAt == start }
        expect(store.trainingElapsed(at: start.addingTimeInterval(3661)) == "01:01:01", "서버 시각 기준 경과 시간")
        expect(store.trainingElapsed(at: start.addingTimeInterval(-10)) == "00:00:00", "음수 경과 시간 차단")
        repository.sessions[0].finish(throwing: Failure.disconnected)
        await wait("세션 구독 실패") { store.canRetrySessionObservation }
        expect(store.currentSession?.startedAt == start, "세션 구독 실패 중 서버 시각 보존")
        store.retrySessionObservation()
        store.retrySessionObservation()
        await wait("세션 재구독") { repository.sessionCount == 2 }
        repository.sessions[1].send(updated(session, status: .running, start: start))
        await wait("세션 재연결 복구") { store.sessionConnectionState == .connected }

        store.finishTraining()
        await wait("종료 쓰기 대기") { repository.hasPendingWrite }
        store.finishTraining()
        // Firestore의 로컬 보류 스냅샷이 ACK보다 먼저 도착해도 결과 화면으로 이동하지 않는다.
        repository.sessions[1].send(updated(session, status: .ended, start: start))
        await wait("보류 ended 수신") { store.currentSession?.status == .ended }
        expect(store.phase == .trainingInProgress && !store.canFinishTraining && repository.recordingCount == 0,
               "종료 ACK 전에 기록 대기·AAR로 이동하지 않음")
        repository.completeWrite(error: Failure.disconnected)
        await wait("종료 실패") { !store.isFinishingTraining }
        expect(store.phase == .trainingInProgress && store.trainingActionError != nil, "종료 실패 후 현재 화면 유지")
        repository.sessions[1].send(updated(session, status: .running, start: start))
        await wait("보류 쓰기 롤백") { store.currentSession?.status == .running }
        store.finishTraining()
        await wait("종료 재시도") { repository.hasPendingWrite }
        repository.completeWrite()
        await wait("결과 준비 진입") { store.phase == .resultsPreparation && repository.recordingCount == 1 }
        expect(store.currentSession?.status == .ended && store.trainingRecords.connectionState == .connecting,
               "종료 ACK 후 첫 기록 스냅샷 대기")
        await wait("세션 구독 종료") { repository.sessions[1].terminationCount == 1 }

        let firstID = UUID(uuidString: store.trainingParticipants[0].id)!
        let secondID = UUID(uuidString: store.trainingParticipants[1].id)!
        let firstDone = record(session.id, firstID, .done)
        let secondDone = record(session.id, secondID, .done)
        repository.recordings[0].send([])
        await wait("빈 스냅샷 수신") { store.trainingRecords.connectionState == .connected }
        expect(store.phase == .resultsPreparation && store.trainingRecords.rows.allSatisfy { $0.state == .waiting }, "빈 목록은 완료 아님")
        repository.recordings[0].send([firstDone, record(session.id, UUID(), .done), record(UUID(), secondID, .done)])
        await wait("일부 기록 수신") { store.trainingRecords.recordings.count == 1 }
        expect(store.phase == .resultsPreparation && store.trainingRecords.terminalCount == 1, "외부 대원·다른 세션·일부 기록으로 통과 금지")
        repository.recordings[0].send([firstDone, record(session.id, firstID, .finishing), secondDone])
        await wait("중복 대원의 진행 중 기록") { store.trainingRecords.recordings.count == 3 }
        expect(store.phase == .resultsPreparation && store.trainingRecords.rows[0].state == .finishing,
               "한 대원의 done 기록 하나로 진행 중 다른 기록을 무시하지 않음")
        repository.recordings[0].send([firstDone, record(session.id, secondID, .recording)])
        await wait("녹화 중 상태") { store.trainingRecords.rows[1].state == .recording }
        repository.recordings[0].finish(throwing: Failure.disconnected)
        await wait("기록 구독 실패") { store.trainingRecords.canRetry }
        expect(store.trainingRecords.terminalCount == 1 && store.phase == .resultsPreparation, "기존 상태 보존·AAR 차단")
        store.retryRecordingObservation()
        store.retryRecordingObservation()
        await wait("기록 재연결") { repository.recordingCount == 2 }
        expect(store.trainingRecords.connectionState == .connecting && !store.trainingRecords.isReadyForAAR,
               "재연결 첫 스냅샷 전 완료 판정 차단")
        repository.recordings[1].send([firstDone, record(session.id, secondID, .failed)])
        await wait("전원 종결 후 AAR") { store.phase == .aar }
        expect(store.selectedParticipants.count == 2 && store.trainingRecords.failedCount == 1,
               "failed도 종결이지만 실패 정보와 참가 명단 유지")
        await wait("AAR에서 기록 구독 정리") { repository.recordings[1].terminationCount == 1 }
        expect(repository.writes == [.running, .running, .ended, .ended], "실패 재시도 외 중복 상태 쓰기 없음")
        store.returnHome()
        repository.recordings[1].send([])
        expect(store.trainingParticipants.isEmpty && store.trainingRecords.recordings.isEmpty, "홈 복귀 시 결과 초기화")
    }

    private static func checkExclusionAndCancellation() async {
        let (store, repository, _) = await readyStore(allReady: false)
        store.startTraining()
        expect(!store.isStartingTraining, "미준비자 포함 일반 시작 거부")
        store.startTrainingExcludingUnreadyParticipants()
        await wait("제외 시작 대기") { repository.hasPendingWrite }
        expect(store.participants.count == 2 && store.trainingParticipants.isEmpty, "ACK 전 대원 목록 제거 금지")
        repository.completeWrite()
        await wait("제외 시작 성공") { store.phase == .trainingInProgress }
        expect(store.trainingParticipants.count == 1 && store.participants.count == 1, "성공 시 준비 대원만 확정")
        store.finishTraining()
        await wait("취소할 종료 쓰기") { repository.hasPendingWrite }
        store.returnHome()
        repository.completeWrite()
        await settle()
        expect(store.phase == .home && store.currentSession == nil && repository.recordingCount == 0,
               "화면 이탈 후 늦은 종료 성공 무시")

        let (other, otherRepository, _) = await readyStore()
        other.startTraining()
        await wait("취소할 시작 쓰기") { otherRepository.hasPendingWrite }
        other.returnHome()
        otherRepository.completeWrite()
        await settle()
        expect(other.phase == .home && !other.isStartingTraining && otherRepository.sessionCount == 0,
               "화면 이탈 후 늦은 시작 성공 무시")
    }

    private static func checkEmptyRosterAndNormalStreamEnd() async {
        let repository = LifecycleRepository()
        let records = TrainingRecordStore(repository: repository)
        var didProceed = false
        records.observe(sessionID: UUID(), participants: []) { didProceed = true }
        await wait("빈 명단 기록 구독") { repository.recordingCount == 1 }
        repository.recordings[0].send([])
        await wait("빈 명단 스냅샷") { records.connectionState == .connected }
        expect(!records.isReadyForAAR && !didProceed, "빈 확정 명단은 allSatisfy로 통과하지 않음")
        repository.recordings[0].finish()
        await wait("기록 스트림 정상 종료도 재연결") { records.canRetry }
        records.reset()

        let (store, sessionRepository, _) = await readyStore()
        store.startTraining()
        await wait("정상 종료 검사 시작") { sessionRepository.hasPendingWrite }
        sessionRepository.completeWrite()
        await wait("세션 구독") { sessionRepository.sessionCount == 1 }
        sessionRepository.sessions[0].finish()
        await wait("세션 스트림 정상 종료도 재연결") { store.canRetrySessionObservation }
        store.returnHome()
    }

    private static func readyStore(allReady: Bool = true) async -> (InstructorStore, LifecycleRepository, [Member]) {
        let repository = LifecycleRepository()
        let store = InstructorStore(
            floorPlans: [DemoFloorPlan(id: "plan", name: "검사 도면", fileName: "plan.png", referenceDistance: 10)],
            sessionRepository: repository, memberRepository: repository, recordingRepository: repository
        )
        store.openSessionCreation()
        store.createSession()
        await wait("검사 세션 생성") { repository.memberCount == 1 }
        let members = [
            Member(id: UUID(), sessionID: store.currentSession!.id, name: "대원 A", isReady: true, lastActiveAt: .now),
            Member(id: UUID(), sessionID: store.currentSession!.id, name: "대원 B", isReady: allReady, lastActiveAt: .now),
        ]
        repository.members[0].send(members)
        await wait("검사 참가자 준비") { store.canRequestTrainingStart }
        return (store, repository, members)
    }

    private static func updated(_ session: Session, status: SessionStatus, start: Date? = nil) -> Session {
        Session(id: session.id, pin: session.pin, name: session.name, status: status,
                startedAt: start, floorPlan: session.floorPlan)
    }

    private static func record(_ sessionID: UUID, _ memberID: UUID, _ state: RecordingState) -> Recording {
        Recording(identity: TrackIdentity(sessionID: sessionID, memberID: memberID, recordingID: UUID()),
                  state: state, lastActiveAt: .now)
    }

    private static func expect(_ condition: Bool, _ message: String) { precondition(condition, message) }
    private static func wait(_ message: String, until condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("시간 내 상태 도달 실패: \(message)")
    }
    private static func settle() async { try? await Task.sleep(for: .milliseconds(30)) }
    private enum Failure: Error { case disconnected }
}

private final class LifecycleFeed<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    private let lock = NSLock()
    private var terminations = 0
    var terminationCount: Int { lock.withLock { terminations } }

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.terminations += 1 }
        }
    }
    func send(_ value: Value) { continuation.yield(value) }
    func finish(throwing error: Error? = nil) { continuation.finish(throwing: error) }
}

private final class LifecycleRepository: SessionRepository, MemberRepository, RecordingRepository, @unchecked Sendable {
    let members = [LifecycleFeed<[Member]>(), LifecycleFeed<[Member]>()]
    let sessions = [LifecycleFeed<Session>(), LifecycleFeed<Session>()]
    let recordings = [LifecycleFeed<[Recording]>(), LifecycleFeed<[Recording]>()]
    private let lock = NSLock()
    private var memberIndex = 0
    private var sessionIndex = 0
    private var recordingIndex = 0
    private var statusWrites: [SessionStatus] = []
    private var pendingWrite: CheckedContinuation<Void, Error>?
    var memberCount: Int { lock.withLock { memberIndex } }
    var sessionCount: Int { lock.withLock { sessionIndex } }
    var recordingCount: Int { lock.withLock { recordingIndex } }
    var writes: [SessionStatus] { lock.withLock { statusWrites } }
    var hasPendingWrite: Bool { lock.withLock { pendingWrite != nil } }

    func createSession(_ session: Session) async throws {}
    func session(forPin pin: String) async throws -> Session { throw RepositoryError.notFound }
    func updateStatus(of session: Session, to status: SessionStatus) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                precondition(pendingWrite == nil, "중복 상태 쓰기")
                statusWrites.append(status)
                pendingWrite = continuation
            }
        }
    }
    func completeWrite(error: Error? = nil) {
        let continuation = lock.withLock { let value = pendingWrite; pendingWrite = nil; return value }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        lock.withLock { defer { sessionIndex += 1 }; return sessions[sessionIndex].stream }
    }
    func join(_ member: Member, pin: String) async throws {}
    func updateReadiness(of member: Member) async throws {}
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        lock.withLock { defer { memberIndex += 1 }; return members[memberIndex].stream }
    }
    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {}
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        lock.withLock { defer { recordingIndex += 1 }; return recordings[recordingIndex].stream }
    }
}
