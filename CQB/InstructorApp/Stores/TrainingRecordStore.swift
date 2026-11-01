import CQBCore
import Foundation
import Observation
import os

/// 교관 앱의 결과 준비 상태. 서버의 Recording 계약과 별개인 표시 모델이다.
nonisolated struct ParticipantRecordingProgress: Identifiable {
    enum State {
        case waiting, recording, finishing, done, failed

        var title: String {
            switch self {
            case .waiting: "기록 수신 대기"
            case .recording: "녹화 중"
            case .finishing: "기록 처리·업로드 중"
            case .done: "완료"
            case .failed: "실패"
            }
        }

        var isTerminal: Bool { self == .done || self == .failed }
    }

    let participant: InstructorParticipant
    let state: State
    var id: String { participant.id }
}

/// 현재 훈련의 확정 참가자와 기록 구독을 소유한다. 파일 업로드는 #47의 책임이다.
@Observable
nonisolated final class TrainingRecordStore {
    enum ConnectionState { case idle, connecting, connected, failed }

    @ObservationIgnored private let repository: any RecordingRepository
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var observationID: UUID?
    @ObservationIgnored private var onReady: (() -> Void)?
    private var sessionID: UUID?
    private(set) var participants: [InstructorParticipant] = []
    private(set) var recordings: [Recording] = []
    private(set) var excludedParticipantIDs: Set<String> = []
    private(set) var connectionState: ConnectionState = .idle
    private(set) var errorMessage: String?

    init(repository: any RecordingRepository) { self.repository = repository }

    var rows: [ParticipantRecordingProgress] {
        participants.map { participant in
            let records = recordings.filter { $0.identity.memberID.uuidString == participant.id }
            let state: ParticipantRecordingProgress.State
            if records.isEmpty { state = .waiting }
            else if records.contains(where: { $0.state == .recording }) { state = .recording }
            else if records.contains(where: { $0.state == .finishing }) { state = .finishing }
            else if records.contains(where: { $0.state == .failed }) { state = .failed }
            else { state = .done }
            return ParticipantRecordingProgress(participant: participant, state: state)
        }
    }

    var terminalCount: Int { rows.filter { $0.state.isTerminal }.count }
    var failedCount: Int { rows.filter { $0.state == .failed }.count }
    var excludedCount: Int { excludedParticipantIDs.count }
    var completedParticipantIDs: Set<String> {
        Set(rows.filter { $0.state == .done }.map(\.id))
    }
    var aarEligibleParticipantIDs: Set<String> {
        completedParticipantIDs.subtracting(excludedParticipantIDs)
    }
    var blockingParticipantIDs: Set<String> {
        Set(rows.filter { !$0.state.isTerminal && !excludedParticipantIDs.contains($0.id) }.map(\.id))
    }
    var canRetry: Bool { connectionState == .failed && sessionID != nil }
    var isReadyForAAR: Bool {
        connectionState == .connected && !participants.isEmpty
            && !aarEligibleParticipantIDs.isEmpty
            && rows.allSatisfy { $0.state.isTerminal }
    }
    var canProceedToAAR: Bool {
        connectionState == .connected && !aarEligibleParticipantIDs.isEmpty
            && blockingParticipantIDs.isEmpty
    }

    @MainActor
    func observe(sessionID: UUID, participants: [InstructorParticipant], onReady: @escaping () -> Void) {
        reset()
        self.sessionID = sessionID
        self.participants = participants
        self.onReady = onReady
        startObservation()
    }

    @MainActor
    func retry() {
        guard canRetry else { return }
        excludedParticipantIDs = []
        startObservation()
    }

    @MainActor
    func excludeParticipant(_ id: String) {
        guard connectionState == .connected,
              let row = rows.first(where: { $0.id == id }),
              !row.state.isTerminal else { return }
        excludedParticipantIDs.insert(id)
    }

    func canExcludeParticipant(_ id: String) -> Bool {
        connectionState == .connected
            && !excludedParticipantIDs.contains(id)
            && rows.contains { $0.id == id && !$0.state.isTerminal }
    }

    /// AAR에서도 실패 정보를 표시하도록 결과는 보존하고 구독만 정리한다.
    @MainActor
    func stop() {
        observationID = nil
        task?.cancel()
        task = nil
        connectionState = .idle
        errorMessage = nil
        onReady = nil
    }

    @MainActor
    func reset() {
        stop()
        sessionID = nil
        participants = []
        recordings = []
        excludedParticipantIDs = []
    }

    @MainActor
    private func startObservation() {
        guard let sessionID else { return }
        task?.cancel()
        let id = UUID()
        observationID = id
        connectionState = .connecting
        errorMessage = nil
        let repository = repository
        task = Task { [weak self] in
            do {
                for try await snapshot in repository.observeRecordings(sessionID: sessionID) {
                    try Task.checkCancellation()
                    guard let self, self.observationID == id, self.sessionID == sessionID else { return }
                    // 다른 세션이나 확정 참가자가 아닌 대원의 기록은 완료 판단에서 제외한다.
                    let expectedIDs = Set(self.participants.map(\.id))
                    self.recordings = snapshot.filter {
                        $0.identity.sessionID == sessionID && expectedIDs.contains($0.identity.memberID.uuidString)
                    }
                    self.connectionState = .connected
                    if self.isReadyForAAR { self.onReady?() }
                }
            } catch {
                guard !Task.isCancelled else { return }
                let failure = error as NSError
                Logger(subsystem: "com.wffmst.cqb", category: "TrainingRecordStore")
                    .error("기록 구독 실패: domain=\(failure.domain, privacy: .public) code=\(failure.code)")
            }
            guard !Task.isCancelled, let self, self.observationID == id else { return }
            self.task = nil
            self.observationID = nil
            self.connectionState = .failed
            self.errorMessage = "기록 상태 연결이 끊어졌습니다. 다시 연결해주세요."
        }
    }
}
