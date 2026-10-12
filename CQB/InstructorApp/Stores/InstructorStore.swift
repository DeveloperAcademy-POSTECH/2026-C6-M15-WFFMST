import CQBCore
import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class InstructorStore {
    enum MemberConnectionState {
        case idle, connecting, connected, failed
    }

    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "InstructorStore")

    let floorPlanDraft: FloorPlanDraftStore
    @ObservationIgnored private let floorPlanFileRepository: any FloorPlanFileRepository
    @ObservationIgnored private let sessionRepository: any SessionRepository
    @ObservationIgnored private let memberRepository: any MemberRepository
    @ObservationIgnored private let pinGenerator: () -> String
    @ObservationIgnored private var floorPlanUploadTask: Task<Void, Never>?
    @ObservationIgnored private var sessionCreationTask: Task<Void, Never>?
    @ObservationIgnored private var memberObservationTask: Task<Void, Never>?
    @ObservationIgnored private var sessionEndTask: Task<Void, Never>?
    @ObservationIgnored private var memberObservationID: UUID?
#if canImport(UIKit)
    private(set) var selectedPlanImage: UIImage?
#endif
    private(set) var phase: InstructorPhase = .home
    private(set) var floorPlans: [DemoFloorPlan]
    private(set) var trainingName = "샘플 훈련"
    private(set) var selectedFloorPlanID: String?
    private(set) var participants: [InstructorParticipant] = []
    private(set) var aarMode: AARMode = .movement
    private(set) var selectedParticipantIDs: Set<String> = []
    private(set) var playbackPosition = 331.0
    private(set) var aarNotice: String?
    private(set) var isUploadingFloorPlan = false
    private(set) var floorPlanUploadError: String?
    private(set) var currentSession: Session?
    private(set) var isCreatingSession = false
    private(set) var sessionCreationError: String?
    private(set) var memberObservationError: String?
    private(set) var memberConnectionState: MemberConnectionState = .idle
    private(set) var isEndingSession = false
    private(set) var sessionEndError: String?
    private var failedFloorPlanRegistration: LocalRegisteredFloorPlan?

    let sampleTrainingElapsed = "00:12:34"
    let playbackDuration = 2172.0
    let maximumVideoCount = 4

    init(
        floorPlans: [DemoFloorPlan] = [],
        floorPlanDraft: FloorPlanDraftStore? = nil,
        floorPlanFileRepository: any FloorPlanFileRepository = DemoFloorPlanFileRepository(),
        sessionRepository: any SessionRepository = DemoSessionRepository(),
        memberRepository: any MemberRepository = DemoMemberRepository(),
        pinGenerator: @escaping () -> String = InstructorStore.makePIN,
        previewSession: Session? = nil,
        previewParticipants: [InstructorParticipant] = []
    ) {
        self.floorPlanDraft = floorPlanDraft ?? FloorPlanDraftStore()
        self.floorPlanFileRepository = floorPlanFileRepository
        self.sessionRepository = sessionRepository
        self.memberRepository = memberRepository
        self.pinGenerator = pinGenerator
        self.floorPlans = floorPlans
        self.currentSession = previewSession
        self.participants = previewParticipants
        if previewSession != nil {
            phase = .teamReadiness
            memberConnectionState = .connected
        }
        selectedFloorPlanID = floorPlans.first?.id
    }

    var selectedFloorPlan: DemoFloorPlan? { floorPlans.first { $0.id == selectedFloorPlanID } }
    var canOpenSessionCreation: Bool { !floorPlans.isEmpty }
    var canCreateSession: Bool {
        !isCreatingSession
            && !trainingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedFloorPlan != nil
    }
    var readyCount: Int { participants.filter(\.isReady).count }
    var unreadyCount: Int { participants.count - readyCount }
    var canStartTraining: Bool { canRequestTrainingStart && unreadyCount == 0 }
    var canRequestTrainingStart: Bool {
        phase == .teamReadiness && currentSession != nil && !isEndingSession
            && memberConnectionState == .connected && readyCount > 0
    }
    var canRetryMemberObservation: Bool {
        phase == .teamReadiness && currentSession != nil && !isEndingSession
            && memberConnectionState == .failed
    }
    var requiresUnreadyExclusionConfirmation: Bool { canRequestTrainingStart && unreadyCount > 0 }
    var canGoBack: Bool {
        [.floorPlanList, .floorPlanCreation, .sessionCreation, .teamReadiness].contains(phase)
            && !isUploadingFloorPlan && !isCreatingSession && !isEndingSession
    }
    var selectedParticipants: [InstructorParticipant] { participants.filter { selectedParticipantIDs.contains($0.id) } }
    var selectionSummary: String {
        if selectedParticipantIDs.count == participants.count && !participants.isEmpty { return "전체 대원" }
        return selectedParticipants.isEmpty ? "대원 선택" : "대원 " + selectedParticipants.map { String($0.number) }.joined(separator: ", ")
    }
    var canSelectAllParticipants: Bool { aarMode == .movement || participants.count <= maximumVideoCount }

    func openFloorPlanList() { phase = .floorPlanList }
    func openFloorPlanCreation() {
        floorPlanDraft.begin()
        phase = .floorPlanCreation
    }
    func openSessionCreation() {
        guard canOpenSessionCreation else { return }
        phase = .sessionCreation
    }
    func registerFloorPlan() {
        guard phase == .floorPlanCreation, !isUploadingFloorPlan,
              let registration = floorPlanDraft.registration() else { return }
        uploadFloorPlan(registration)
    }
    func retryFloorPlanUpload() {
        guard phase == .floorPlanCreation, !isUploadingFloorPlan,
              let registration = failedFloorPlanRegistration else { return }
        uploadFloorPlan(registration)
    }
    func setTrainingName(_ value: String) {
        guard !isCreatingSession else { return }
        trainingName = value
    }
    func selectFloorPlan(_ id: String?) {
        guard !isCreatingSession else { return }
        guard id == nil || floorPlans.contains(where: { $0.id == id }) else { return }
        selectedFloorPlanID = id
#if canImport(UIKit)
        selectedPlanImage = selectedFloorPlan?.registeredPlan.flatMap { UIImage(data: $0.image.pngData) }
#endif
    }
    func createSession() {
        guard phase == .sessionCreation, canCreateSession, let floorPlan = selectedFloorPlan else { return }
        stopObservingMembers()
        sessionCreationTask?.cancel()
        isCreatingSession = true
        sessionCreationError = nil
        sessionEndError = nil
        participants = []
        currentSession = nil

        let name = trainingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = floorPlan.reference
        let repository = sessionRepository
        let makePIN = pinGenerator
        sessionCreationTask = Task { [weak self] in
            do {
                let session = try await Self.createSession(
                    name: name,
                    floorPlan: reference,
                    repository: repository,
                    pinGenerator: makePIN
                )
                try Task.checkCancellation()
                guard let self, self.phase == .sessionCreation else { return }
                self.currentSession = session
                self.isCreatingSession = false
                self.sessionCreationTask = nil
                self.phase = .teamReadiness
                self.startObservingMembers(for: session)
            } catch {
                guard let self, !(error is CancellationError), self.phase == .sessionCreation else { return }
                let failure = error as NSError
                Self.logger.error("세션 생성 실패: domain=\(failure.domain, privacy: .public) code=\(failure.code) description=\(failure.localizedDescription, privacy: .private)")
                self.isCreatingSession = false
                self.sessionCreationTask = nil
                self.sessionCreationError = Self.sessionCreationMessage(for: error)
            }
        }
    }
    func startTraining() {
        guard phase == .teamReadiness, canStartTraining else { return }
        stopObservingMembers()
        phase = .trainingInProgress
    }
    func startTrainingExcludingUnreadyParticipants() {
        guard phase == .teamReadiness, canRequestTrainingStart else { return }
        stopObservingMembers()
        participants.removeAll { !$0.isReady }
        phase = .trainingInProgress
    }
    func finishTraining() {
        guard phase == .trainingInProgress else { return }
        aarMode = .movement
        selectedParticipantIDs = Set(participants.map(\.id))
        playbackPosition = 331
        aarNotice = nil
        phase = .aar
    }
    func changeAARMode(to mode: AARMode) {
        if mode == .video, selectedParticipantIDs.count > maximumVideoCount {
            aarNotice = "영상은 최대 \(maximumVideoCount)명까지 볼 수 있습니다. 표시 대상을 \(maximumVideoCount)명 이하로 선택해주세요."
            return
        }
        aarMode = mode
        aarNotice = nil
    }
    func isParticipantSelected(_ id: String) -> Bool { selectedParticipantIDs.contains(id) }
    func canToggleParticipant(_ id: String) -> Bool {
        guard participants.contains(where: { $0.id == id }) else { return false }
        return aarMode == .movement || selectedParticipantIDs.contains(id) || selectedParticipantIDs.count < maximumVideoCount
    }
    func toggleParticipantSelection(_ id: String) {
        guard canToggleParticipant(id) else {
            aarNotice = "영상은 최대 \(maximumVideoCount)명까지 선택할 수 있습니다."
            return
        }
        if selectedParticipantIDs.contains(id) {
            selectedParticipantIDs.remove(id)
        } else {
            selectedParticipantIDs.insert(id)
        }
        aarNotice = nil
    }
    func selectAllParticipants() {
        guard canSelectAllParticipants else { return }
        selectedParticipantIDs = Set(participants.map(\.id))
        aarNotice = nil
    }
    func setPlaybackPosition(_ value: Double) {
        guard value.isFinite else { return }
        playbackPosition = min(max(0, value), playbackDuration)
    }
    func finishAAR() {
        guard phase == .aar else { return }
        phase = .aarCompleted
    }
    func returnHome() {
        cancelSessionWork()
        trainingName = "샘플 훈련"
        selectFloorPlan(floorPlans.first?.id)
        participants = []
        selectedParticipantIDs = []
        aarMode = .movement
        aarNotice = nil
        currentSession = nil
        playbackPosition = 331
        phase = .home
    }
    func goBack() {
        guard !isUploadingFloorPlan, !isCreatingSession, !isEndingSession else { return }
        switch phase {
        case .floorPlanList: phase = .home
        case .sessionCreation:
            cancelSessionCreation()
            phase = .home
        case .floorPlanCreation:
            clearFloorPlanUpload()
            if floorPlanDraft.step == .scaling {
                floorPlanDraft.returnToEditing()
            } else {
                floorPlanDraft.reset()
                phase = .floorPlanList
            }
        case .teamReadiness:
            endCurrentSession()
        default: break
        }
    }

    func retryMemberObservation() {
        guard canRetryMemberObservation, memberObservationTask == nil, let currentSession else { return }
        startObservingMembers(for: currentSession)
    }

    private static func createSession(
        name: String,
        floorPlan: FloorPlanReference,
        repository: any SessionRepository,
        pinGenerator: () -> String
    ) async throws -> Session {
        for _ in 0..<5 {
            try Task.checkCancellation()
            let session = Session(
                id: UUID(),
                pin: pinGenerator(),
                name: name,
                status: .waiting,
                floorPlan: floorPlan
            )
            do {
                try await repository.createSession(session)
                return session
            } catch RepositoryError.pinTaken {
                continue
            }
        }
        throw RepositoryError.pinTaken
    }

    nonisolated private static func makePIN() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private func startObservingMembers(for session: Session) {
        stopObservingMembers()
        memberObservationError = nil
        memberConnectionState = .connecting
        let observationID = UUID()
        memberObservationID = observationID
        let repository = memberRepository
        memberObservationTask = Task { [weak self] in
            do {
                for try await members in repository.observeMembers(sessionID: session.id) {
                    try Task.checkCancellation()
                    guard let self,
                          self.memberObservationID == observationID,
                          self.phase == .teamReadiness,
                          self.currentSession?.id == session.id else { return }
                    self.participants = Self.displayParticipants(from: members)
                    self.memberConnectionState = .connected
                }
            } catch {
                guard !(error is CancellationError), !Task.isCancelled else { return }
                let failure = error as NSError
                Self.logger.error("참가자 구독 실패: domain=\(failure.domain, privacy: .public) code=\(failure.code) description=\(failure.localizedDescription, privacy: .private)")
            }
            // 오류뿐 아니라 예기치 않은 정상 종료도 재연결이 필요하다.
            guard !Task.isCancelled, let self,
                  self.memberObservationID == observationID,
                  self.phase == .teamReadiness else { return }
            self.memberObservationTask = nil
            self.memberObservationID = nil
            self.memberConnectionState = .failed
            self.memberObservationError = "참가자 준비 상태 연결이 끊어졌습니다. 다시 연결해주세요."
        }
    }

    private func stopObservingMembers() {
        memberObservationID = nil
        memberObservationTask?.cancel()
        memberObservationTask = nil
        memberConnectionState = .idle
        memberObservationError = nil
    }

    private func endCurrentSession() {
        guard !isEndingSession else { return }
        guard let session = currentSession else {
            stopObservingMembers()
            participants = []
            currentSession = nil
            phase = .sessionCreation
            return
        }
        stopObservingMembers()
        isEndingSession = true
        sessionEndError = nil
        let repository = sessionRepository
        sessionEndTask = Task { [weak self] in
            do {
                try await repository.updateStatus(of: session, to: .ended)
                try Task.checkCancellation()
                guard let self, self.phase == .teamReadiness, self.currentSession?.id == session.id else { return }
                self.isEndingSession = false
                self.sessionEndTask = nil
                self.participants = []
                self.currentSession = nil
                self.phase = .sessionCreation
            } catch {
                guard let self, !(error is CancellationError), self.phase == .teamReadiness else { return }
                self.isEndingSession = false
                self.sessionEndTask = nil
                self.sessionEndError = "세션을 종료하지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해주세요."
                if self.currentSession?.id == session.id {
                    self.startObservingMembers(for: session)
                }
            }
        }
    }

    private func cancelSessionCreation() {
        sessionCreationTask?.cancel()
        sessionCreationTask = nil
        isCreatingSession = false
        sessionCreationError = nil
    }

    private func cancelSessionWork() {
        cancelSessionCreation()
        stopObservingMembers()
        sessionEndTask?.cancel()
        sessionEndTask = nil
        isEndingSession = false
        sessionEndError = nil
    }

    private static func displayParticipants(from members: [Member]) -> [InstructorParticipant] {
        members
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .enumerated()
            .map { index, member in
                InstructorParticipant(
                    id: member.id.uuidString,
                    number: index + 1,
                    name: member.name,
                    isReady: member.isReady,
                    x: 0.22 + Double(index % 4) * 0.17,
                    y: index < 4 ? 0.5 : 0.68
                )
            }
    }

    private static func sessionCreationMessage(for error: Error) -> String {
        if error as? RepositoryError == .pinTaken {
            return "사용 가능한 PIN을 만들지 못했습니다. 다시 시도해주세요."
        }
        return "세션을 만들지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해주세요."
    }

    private func uploadFloorPlan(_ registration: LocalRegisteredFloorPlan) {
        isUploadingFloorPlan = true
        floorPlanUploadError = nil
        failedFloorPlanRegistration = registration
        let repository = floorPlanFileRepository
        let preparation = Task.detached(priority: .userInitiated) {
            try LocalFloorPlanFileBuilder.build(from: registration)
        }
        floorPlanUploadTask = Task { [weak self] in
            do {
                let upload = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: {
                    preparation.cancel()
                }
                try Task.checkCancellation()
                try await repository.upload(upload.files, for: upload.reference)
                try Task.checkCancellation()
                guard let self, self.phase == .floorPlanCreation else { return }
                let plan = DemoFloorPlan(
                    id: upload.registration.id.uuidString,
                    name: upload.registration.name,
                    fileName: upload.registration.image.fileName,
                    referenceDistance: upload.registration.scale.meters,
                    reference: upload.reference,
                    registeredPlan: upload.registration
                )
                self.floorPlans.append(plan)
                self.selectFloorPlan(plan.id)
                self.clearFloorPlanUpload()
                self.floorPlanDraft.reset()
                self.phase = .floorPlanList
            } catch {
                guard let self, !(error is CancellationError) else { return }
                self.isUploadingFloorPlan = false
                self.floorPlanUploadTask = nil
                self.floorPlanUploadError = Self.floorPlanUploadMessage(for: error)
            }
        }
    }

    private func clearFloorPlanUpload() {
        floorPlanUploadTask?.cancel()
        floorPlanUploadTask = nil
        isUploadingFloorPlan = false
        floorPlanUploadError = nil
        failedFloorPlanRegistration = nil
    }

    private static func floorPlanUploadMessage(for error: Error) -> String {
        switch error as? RepositoryError {
        case .fileTooLarge:
            "도면 파일이 업로드 제한인 20MB를 초과했습니다."
        case .integrityMismatch:
            "도면 파일의 무결성을 확인하지 못했습니다. 다시 시도해주세요."
        case .none:
            "도면을 업로드하지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해주세요."
        default:
            "도면을 업로드하지 못했습니다. 잠시 후 다시 시도해주세요."
        }
    }
}
