import CQBCore
import Foundation

/// 이전 훈련 기록 목록 복원, 기록에서 AAR 열기·닫기, 서버 영상과 함께 삭제를 서버 없이 검증한다.
@MainActor
enum TrainingHistoryChecks {
    static func run() async {
        checkLoadAndRetry()
        await checkOpenAndReturnHome()
        await checkOpenFailureAndCancellation()
        await checkLeavingWhileOpening()
        await checkDeletion()
        print("PASS: 이전 훈련 기록 복원·재시도, 기록에서 AAR 열기·홈 복귀, 열기 실패·취소·화면 이탈, 서버 영상과 함께 삭제")
    }

    private static func checkLoadAndRetry() {
        let older = makeRecord(minutesAfterBase: 0)
        let newer = makeRecord(minutesAfterBase: 60)
        let repository = InMemoryTrainingHistoryRepository(records: [older, newer])
        repository.fetchError = Failure.unavailable
        let store = InstructorStore(trainingHistoryRepository: repository)
        store.loadTrainingHistory()
        expect(store.trainingHistoryError != nil && store.trainingHistory.isEmpty, "복원 실패 안내")
        repository.fetchError = nil
        store.retryTrainingHistoryLoad()
        expect(store.trainingHistoryState == .loaded && store.trainingHistory == [newer, older], "재시도 후 최신순 복원")
        store.loadTrainingHistory()
        expect(store.trainingHistory == [newer, older], "이미 불러온 목록은 다시 읽지 않음")
    }

    private static func checkOpenAndReturnHome() async {
        let record = makeRecord(minutesAfterBase: 0)
        let session = makeSession(for: record)
        let feeds = HistoryFeeds()
        let store = InstructorStore(
            floorPlans: [InstructorFloorPlan(id: "plan", name: "검사 도면", fileName: "plan.png", referenceDistance: 10)],
            sessionRepository: feeds, memberRepository: feeds,
            trainingHistory: [record]
        )
        store.openTrainingHistoryRecord(record.sessionID)
        expect(store.openingTrainingHistorySessionID == record.sessionID && !store.canSelectTrainingHistoryRecord,
               "여는 중에는 다른 기록 선택 차단")
        await wait("세션·대원 구독") { feeds.sessionCount == 1 && feeds.memberCount == 1 }
        feeds.sessions[0].send(session)
        feeds.members[0].send([
            Member(id: UUID(), sessionID: session.id, name: "대원 A", isReady: true, lastActiveAt: .now),
            Member(id: UUID(), sessionID: session.id, name: "대원 B", isReady: true, lastActiveAt: .now),
        ])
        await wait("기록에서 AAR 진입") { store.phase == .aar }
        expect(store.isReviewingTrainingHistory && store.currentSession?.id == record.sessionID
               && store.aarParticipants.count == 2 && store.selectedParticipantIDs.isEmpty
               && store.trainingStartedAt == session.startedAt && store.openingTrainingHistorySessionID == nil,
               "지난 세션의 모든 대원을 재생 대상으로 열고 초기 선택은 비움")
        await wait("첫 값만 받고 구독 정리") {
            feeds.sessions[0].terminationCount == 1 && feeds.members[0].terminationCount == 1
        }
        store.finishAAR()
        expect(store.phase == .home && !store.isReviewingTrainingHistory && store.currentSession == nil
               && store.aarParticipantIDs.isEmpty,
               "기록에서 연 AAR은 AAR 종료 화면 없이 홈으로")
        expect(store.trainingHistory == [record], "AAR을 닫아도 목록 유지")
    }

    private static func checkOpenFailureAndCancellation() async {
        let record = makeRecord(minutesAfterBase: 0)
        let feeds = HistoryFeeds()
        let store = InstructorStore(sessionRepository: feeds, memberRepository: feeds, trainingHistory: [record])
        store.openTrainingHistory()
        store.openTrainingHistoryRecord(record.sessionID)
        await wait("실패할 열기 구독") { feeds.sessionCount == 1 }
        feeds.sessions[0].finish()
        feeds.members[0].send([])
        await wait("세션 없음 안내") { store.trainingHistoryOpenError != nil }
        expect(store.phase == .trainingHistory && store.openingTrainingHistorySessionID == nil
               && store.trainingHistory == [record],
               "열기 실패 시 목록에 남기고 다시 누를 수 있음")
        store.dismissTrainingHistoryOpenError()

        store.openTrainingHistoryRecord(record.sessionID)
        await wait("취소할 열기 구독") { feeds.sessionCount == 2 }
        store.goBack()
        expect(store.phase == .home && store.openingTrainingHistorySessionID == nil, "뒤로 가면 열기 취소")
        feeds.sessions[1].send(makeSession(for: record))
        feeds.members[1].send([])
        await settle()
        expect(store.phase == .home && !store.isReviewingTrainingHistory, "화면 이탈 후 늦은 응답 무시")
    }

    /// 홈에서 기록을 누르고 응답 전에 다른 화면으로 가도 기록 선택이 잠기지 않는다.
    private static func checkLeavingWhileOpening() async {
        let record = makeRecord(minutesAfterBase: 0)
        let feeds = HistoryFeeds()
        let store = InstructorStore(sessionRepository: feeds, memberRepository: feeds, trainingHistory: [record])

        store.openTrainingHistoryRecord(record.sessionID)
        await wait("홈에서 연 기록 구독") { feeds.sessionCount == 1 && feeds.memberCount == 1 }
        store.openTrainingHistory()
        feeds.sessions[0].send(makeSession(for: record))
        feeds.members[0].send([])
        await wait("응답 후 로딩 정리") { store.openingTrainingHistorySessionID == nil }
        expect(store.phase == .trainingHistory && !store.isReviewingTrainingHistory
               && store.trainingHistoryOpenError == nil && store.canSelectTrainingHistoryRecord,
               "모두보기로 이동한 뒤 성공 응답은 AAR로 넘어가지 않고 선택 잠금도 풀림")

        store.goBack()
        store.openTrainingHistoryRecord(record.sessionID)
        await wait("두 번째 기록 구독") { feeds.sessionCount == 2 && feeds.memberCount == 2 }
        store.openFloorPlanList()
        feeds.sessions[1].finish()
        feeds.members[1].send([])
        await wait("실패 응답 후 로딩 정리") { store.openingTrainingHistorySessionID == nil }
        expect(store.phase == .floorPlanList && store.trainingHistoryOpenError == nil,
               "다른 화면으로 간 뒤 실패 응답은 안내하지 않음")
        store.goBack()
        expect(store.phase == .home && store.canSelectTrainingHistoryRecord, "홈으로 돌아오면 기록을 다시 누를 수 있음")
    }

    private static func checkDeletion() async {
        let first = makeRecord(minutesAfterBase: 0)
        let second = makeRecord(minutesAfterBase: 60)
        let repository = InMemoryTrainingHistoryRepository(records: [first, second])
        let deleter = RecordingVideoDeleter()
        let store = InstructorStore(trainingHistoryRepository: repository, trainingVideoDeleter: deleter)
        store.loadTrainingHistory()
        store.deleteTrainingHistoryRecord(first.sessionID)
        expect(store.deletingTrainingHistorySessionID == nil, "목록 화면 밖에서는 삭제하지 않음")

        store.openTrainingHistory()
        deleter.failure = Failure.unavailable
        store.deleteTrainingHistoryRecord(first.sessionID)
        expect(store.deletingTrainingHistorySessionID == first.sessionID && !store.canSelectTrainingHistoryRecord,
               "삭제 중에는 다른 기록 선택 차단")
        await wait("서버 영상 삭제 실패") { store.deletingTrainingHistorySessionID == nil }
        expect(store.trainingHistoryDeletionError != nil && store.trainingHistory == [second, first]
               && (try? repository.fetchAll()) == [second, first],
               "서버 삭제 실패 시 목록에 남겨 다시 시도")

        deleter.failure = nil
        store.deleteTrainingHistoryRecord(first.sessionID)
        await wait("삭제 완료") { store.deletingTrainingHistorySessionID == nil }
        expect(deleter.deletedSessionIDs == [first.sessionID, first.sessionID], "요청한 세션 영상만 삭제")
        expect(store.trainingHistoryDeletionError == nil && store.trainingHistory == [second]
               && (try? repository.fetchAll()) == [second],
               "서버 영상을 지운 뒤 기기 목록에서 삭제")
    }

    static func makeRecord(minutesAfterBase minutes: Double) -> TrainingHistoryRecord {
        let startedAt = Date(timeIntervalSince1970: 1_760_000_000 + minutes * 60)
        return TrainingHistoryRecord(
            sessionID: UUID(),
            trainingName: "검사 훈련",
            floorPlan: FloorPlanReference(
                floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000126")!,
                navigationSHA256: "history-hash"
            ),
            floorPlanName: "검사 도면",
            participantNames: ["대원 A", "대원 B"],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(804)
        )
    }

    private static func makeSession(for record: TrainingHistoryRecord) -> Session {
        Session(id: record.sessionID, pin: "000126", name: record.trainingName, status: .ended,
                startedAt: record.startedAt, floorPlan: record.floorPlan)
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
    private enum Failure: Error { case unavailable }
}

private final class RecordingVideoDeleter: TrainingVideoDeleting, @unchecked Sendable {
    private let lock = NSLock()
    private var deleted: [UUID] = []
    private var error: Error?
    var deletedSessionIDs: [UUID] { lock.withLock { deleted } }
    var failure: Error? {
        get { lock.withLock { error } }
        set { lock.withLock { error = newValue } }
    }

    func deleteVideos(sessionID: UUID) async throws {
        let failure = lock.withLock { () -> Error? in
            deleted.append(sessionID)
            return error
        }
        if let failure { throw failure }
    }
}

private final class HistoryFeed<Value: Sendable>: @unchecked Sendable {
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

private final class HistoryFeeds: SessionRepository, MemberRepository, @unchecked Sendable {
    let sessions = [HistoryFeed<Session>(), HistoryFeed<Session>()]
    let members = [HistoryFeed<[Member]>(), HistoryFeed<[Member]>()]
    private let lock = NSLock()
    private var sessionIndex = 0
    private var memberIndex = 0
    var sessionCount: Int { lock.withLock { sessionIndex } }
    var memberCount: Int { lock.withLock { memberIndex } }

    func createSession(_ session: Session) async throws {}
    func session(forPin pin: String) async throws -> Session { throw RepositoryError.notFound }
    func updateStatus(of session: Session, to status: SessionStatus) async throws {}
    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> {
        lock.withLock { defer { sessionIndex += 1 }; return sessions[sessionIndex].stream }
    }
    func join(_ member: Member, pin: String) async throws {}
    func updateReadiness(of member: Member) async throws {}
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> {
        lock.withLock { defer { memberIndex += 1 }; return members[memberIndex].stream }
    }
}
