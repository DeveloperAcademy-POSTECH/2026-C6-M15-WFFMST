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

    enum FloorPlanCatalogState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    enum FloorPlanDetailState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    enum FloorPlanListPreviewState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private enum FloorPlanRegistrationError: Error, Equatable {
        case localSave
    }

    private enum SessionCreationError: Error {
        case worldMapMismatch
    }

    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "InstructorStore")

    let floorPlanDraft: FloorPlanDraftStore
    let trainingRecords: TrainingRecordStore
    @ObservationIgnored private let floorPlanFileRepository: any FloorPlanFileRepository
    @ObservationIgnored private let worldMapFileRepository: (any WorldMapFileRepository)?
    @ObservationIgnored private let floorPlanListPreviewLoader: any FloorPlanListPreviewLoading
    @ObservationIgnored private let floorPlanCatalogRepository: any FloorPlanCatalogRepository
    @ObservationIgnored private let sessionRepository: any SessionRepository
    @ObservationIgnored private let memberRepository: any MemberRepository
    @ObservationIgnored private let pinGenerator: () -> String
    @ObservationIgnored private var floorPlanUploadTask: Task<Void, Never>?
    @ObservationIgnored private var floorPlanDetailTask: Task<Void, Never>?
    @ObservationIgnored private var floorPlanListPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var sessionCreationTask: Task<Void, Never>?
    @ObservationIgnored private var memberObservationTask: Task<Void, Never>?
    @ObservationIgnored private var sessionEndTask: Task<Void, Never>?
    @ObservationIgnored private var memberObservationID: UUID?
    @ObservationIgnored private var trainingActionTask: Task<Void, Never>?
    @ObservationIgnored private var trainingActionID: UUID?
    @ObservationIgnored private var sessionObservationTask: Task<Void, Never>?
    @ObservationIgnored private var sessionObservationID: UUID?
#if canImport(UIKit)
    private(set) var selectedPlanImage: UIImage?
    private(set) var floorPlanDetailImage: UIImage?
    private(set) var floorPlanDetailMaskImage: UIImage?
    private(set) var floorPlanListPreviewImage: UIImage?
    private(set) var floorPlanListPreviewMaskImage: UIImage?
#endif
    private(set) var phase: InstructorPhase = .home
    private(set) var floorPlans: [InstructorFloorPlan]
    private(set) var floorPlanCatalogState: FloorPlanCatalogState
    private(set) var floorPlanDetailState: FloorPlanDetailState = .idle
    private(set) var floorPlanListPreviewState: FloorPlanListPreviewState = .idle
    private(set) var viewedFloorPlanID: String?
    private(set) var previewedFloorPlanID: String?
    private(set) var floorPlanDeletionError: String?
    private(set) var trainingName = "샘플 훈련"
    private(set) var selectedFloorPlanID: String?
    private(set) var participants: [InstructorParticipant] = []
    private(set) var aarScreen: AARScreen = .floorPlan
    /// 도면 화면의 확대 배율과 이동량. 영상 화면 왕복 중에는 유지하고 새 AAR에서 초기화한다.
    private(set) var aarFloorPlanViewport = AARFloorPlanViewport.identity
    /// 기록 업로드를 완료했거나 결과 준비 화면에서 명시적으로 포함된 AAR 재생 대상.
    private(set) var aarParticipantIDs: Set<String> = []
    /// 최근 선택한 대원부터 영상 슬롯 1, 2, 3, 4에 배치한다.
    private(set) var selectedParticipantIDs: [String] = []
    /// 음소거를 직접 해제한 선택 대원. 선택에서 빠지면 함께 제거한다.
    private(set) var unmutedParticipantIDs: Set<String> = []
    private(set) var playbackPosition = 331.0
    private(set) var isUploadingFloorPlan = false
    private(set) var floorPlanUploadError: String?
    private(set) var currentSession: Session?
    private(set) var isCreatingSession = false
    private(set) var sessionCreationError: String?
    private(set) var memberObservationError: String?
    private(set) var memberConnectionState: MemberConnectionState = .idle
    private(set) var isEndingSession = false
    private(set) var sessionEndError: String?
    private(set) var trainingStartedAt: Date?
    private(set) var isStartingTraining = false
    private(set) var isFinishingTraining = false
    private(set) var trainingActionError: String?
    private(set) var sessionConnectionState: MemberConnectionState = .idle
    private(set) var sessionObservationError: String?
    private(set) var trainingParticipants: [InstructorParticipant] = []
    private var failedFloorPlanRegistration: LocalRegisteredFloorPlan?
    private var failedWorldMapDraft: LocalWorldMapScanDraft?
    private var failedReplacementFloorPlanID: String?
    private var floorPlanDetailSnapshot: LocalFloorPlanSnapshot?
    private var editingFloorPlanID: String?

    let playbackDuration = 2172.0
    let maximumVideoCount = 4

    init(
        floorPlans: [InstructorFloorPlan] = [],
        floorPlanDraft: FloorPlanDraftStore? = nil,
        floorPlanFileRepository: any FloorPlanFileRepository = DemoFloorPlanFileRepository(),
        worldMapFileRepository: (any WorldMapFileRepository)? = nil,
        floorPlanListPreviewLoader: (any FloorPlanListPreviewLoading)? = nil,
        floorPlanCatalogRepository: (any FloorPlanCatalogRepository)? = nil,
        sessionRepository: any SessionRepository = DemoSessionRepository(),
        memberRepository: any MemberRepository = DemoMemberRepository(),
        recordingRepository: any RecordingRepository = DemoRecordingRepository(),
        pinGenerator: @escaping () -> String = InstructorStore.makePIN,
        previewSession: Session? = nil,
        previewParticipants: [InstructorParticipant] = [],
        previewPhase: InstructorPhase = .teamReadiness
    ) {
        self.floorPlanDraft = floorPlanDraft ?? FloorPlanDraftStore()
        self.floorPlanFileRepository = floorPlanFileRepository
        self.worldMapFileRepository = worldMapFileRepository
        self.floorPlanListPreviewLoader = floorPlanListPreviewLoader
            ?? LocalFloorPlanListPreviewLoader(repository: floorPlanFileRepository)
        self.floorPlanCatalogRepository = floorPlanCatalogRepository ?? DemoFloorPlanCatalogRepository()
        self.sessionRepository = sessionRepository
        self.memberRepository = memberRepository
        self.trainingRecords = TrainingRecordStore(repository: recordingRepository)
        self.pinGenerator = pinGenerator
        self.floorPlans = floorPlans
        self.floorPlanCatalogState = floorPlans.isEmpty ? .idle : .loaded
        self.currentSession = previewSession
        self.trainingStartedAt = previewSession?.startedAt
        self.participants = previewParticipants
        if previewSession != nil {
            phase = previewPhase
            memberConnectionState = .connected
            if previewPhase != .teamReadiness {
                trainingParticipants = previewParticipants
                aarParticipantIDs = Set(previewParticipants.map(\.id))
            }
        }
        selectedFloorPlanID = floorPlans.first?.id
    }

    var selectedFloorPlan: InstructorFloorPlan? { floorPlans.first { $0.id == selectedFloorPlanID } }
    var viewedFloorPlan: InstructorFloorPlan? { floorPlans.first { $0.id == viewedFloorPlanID } }
    var previewedFloorPlan: InstructorFloorPlan? { floorPlans.first { $0.id == previewedFloorPlanID } }
    var isEditingFloorPlan: Bool { phase == .floorPlanEditing }
    var canOpenSessionCreation: Bool { floorPlanCatalogState == .loaded && !floorPlans.isEmpty }
    var isLoadingFloorPlans: Bool { floorPlanCatalogState == .loading }
    var floorPlanCatalogError: String? {
        guard case .failed(let message) = floorPlanCatalogState else { return nil }
        return message
    }
    var canCreateSession: Bool {
        !isCreatingSession
            && !trainingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedFloorPlan != nil
    }
    var readyCount: Int { participants.filter(\.isReady).count }
    var unreadyCount: Int { participants.count - readyCount }
    var canStartTraining: Bool { canRequestTrainingStart && unreadyCount == 0 }
    var canRequestTrainingStart: Bool {
        phase == .teamReadiness && currentSession != nil && !isEndingSession && !isStartingTraining
            && memberConnectionState == .connected && readyCount > 0
    }
    var canRetryMemberObservation: Bool {
        phase == .teamReadiness && currentSession != nil && !isEndingSession && !isStartingTraining
            && memberConnectionState == .failed
    }
    var requiresUnreadyExclusionConfirmation: Bool { canRequestTrainingStart && unreadyCount > 0 }
    var canGoBack: Bool {
        [.floorPlanList, .floorPlanDetail, .floorPlanCreation, .floorPlanEditing,
         .sessionCreation, .teamReadiness].contains(phase)
            && !isUploadingFloorPlan && !isCreatingSession && !isEndingSession && !isStartingTraining
    }
    var canFinishTraining: Bool { phase == .trainingInProgress && !isFinishingTraining }
    var canRetrySessionObservation: Bool {
        phase == .trainingInProgress && sessionConnectionState == .failed && !isFinishingTraining
    }
    func trainingElapsed(at now: Date) -> String? {
        guard trainingStartedAt != nil else { return nil }
        return formattedTrainingElapsed(at: now)
    }
    var aarParticipants: [InstructorParticipant] {
        participants.filter { aarParticipantIDs.contains($0.id) }
    }
    var selectedParticipants: [InstructorParticipant] {
        let participantsByID = Dictionary(uniqueKeysWithValues: aarParticipants.map { ($0.id, $0) })
        return selectedParticipantIDs.compactMap { participantsByID[$0] }
    }
    var selectionSummary: String {
        selectedParticipants.isEmpty
            ? "대원 선택"
            : "대원 " + selectedParticipants.map { String($0.number) }.joined(separator: ", ")
    }
    var canOpenAARVideoScreen: Bool { phase == .aar && !selectedParticipantIDs.isEmpty }

    func formattedTrainingElapsed(at date: Date) -> String {
        guard let trainingStartedAt else { return Self.formatTrainingElapsed(0) }
        return Self.formatTrainingElapsed(date.timeIntervalSince(trainingStartedAt))
    }

    nonisolated static func formatTrainingElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func openFloorPlanList() {
        phase = .floorPlanList
        selectDefaultFloorPlanPreviewIfNeeded()
    }
    func loadFloorPlans() {
        guard floorPlanCatalogState == .idle || floorPlanCatalogError != nil else { return }
        floorPlanCatalogState = .loading
        do {
            let restored = try floorPlanCatalogRepository.fetchAll()
            floorPlans = restored
            let nextSelection = selectedFloorPlanID.flatMap { selected in
                restored.contains(where: { $0.id == selected }) ? selected : nil
            } ?? restored.first?.id
            selectFloorPlan(nextSelection)
            floorPlanCatalogState = .loaded
            selectDefaultFloorPlanPreviewIfNeeded()
        } catch {
            Self.logger.error("도면 목록 복원 실패: \(error.localizedDescription, privacy: .private)")
            floorPlanCatalogState = .failed("등록한 도면을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.")
        }
    }

    func retryFloorPlanCatalogLoad() {
        guard floorPlanCatalogError != nil else { return }
        loadFloorPlans()
    }

    func selectFloorPlanPreview(_ id: String) {
        guard phase == .floorPlanList,
              let floorPlan = floorPlans.first(where: { $0.id == id }) else { return }
        if previewedFloorPlanID == id,
           (floorPlanListPreviewState == .loading || floorPlanListPreviewState == .loaded) {
            return
        }
        loadFloorPlanListPreview(floorPlan)
    }

    func retryFloorPlanListPreview() {
        guard phase == .floorPlanList,
              case .failed = floorPlanListPreviewState,
              let floorPlan = previewedFloorPlan else { return }
        loadFloorPlanListPreview(floorPlan)
    }

    func openFloorPlanDetail(_ id: String) {
        guard floorPlanCatalogState == .loaded,
              let plan = floorPlans.first(where: { $0.id == id }) else { return }
        cancelFloorPlanDetailLoad()
        viewedFloorPlanID = id
        floorPlanDeletionError = nil
        floorPlanDetailState = .loading
        phase = .floorPlanDetail
        loadFloorPlanDetail(plan)
    }

    func retryFloorPlanDetailLoad() {
        guard phase == .floorPlanDetail,
              case .failed = floorPlanDetailState,
              let plan = viewedFloorPlan else { return }
        floorPlanDetailState = .loading
        loadFloorPlanDetail(plan)
    }

    func beginFloorPlanMaskEditing() {
        guard phase == .floorPlanDetail,
              floorPlanDetailState == .loaded,
              let snapshot = floorPlanDetailSnapshot,
              let viewedFloorPlanID else { return }
        editingFloorPlanID = viewedFloorPlanID
        floorPlanDraft.beginMaskEditing(snapshot)
        floorPlanUploadError = nil
        phase = .floorPlanEditing
    }

    func saveFloorPlanMaskEdit() {
        guard phase == .floorPlanEditing, !isUploadingFloorPlan,
              let editingFloorPlanID,
              let target = floorPlans.first(where: { $0.id == editingFloorPlanID }),
              let registration = floorPlanDraft.maskEditingRegistration() else { return }
        uploadFloorPlan(registration, replacing: target)
    }

    func deleteViewedFloorPlan() {
        guard phase == .floorPlanDetail, !isUploadingFloorPlan,
              let id = viewedFloorPlanID,
              let deletedIndex = floorPlans.firstIndex(where: { $0.id == id }) else { return }
        floorPlanDeletionError = nil
        do {
            try floorPlanCatalogRepository.delete(id: id)
            floorPlans.removeAll { $0.id == id }
            let adjacentID = floorPlans.isEmpty
                ? nil
                : floorPlans[min(deletedIndex, floorPlans.count - 1)].id
            if previewedFloorPlanID == id {
                clearFloorPlanListPreview()
            }
            if selectedFloorPlanID == id {
                selectFloorPlan(adjacentID)
            }
            clearFloorPlanDetail()
            phase = .floorPlanList
            if let adjacentID {
                selectFloorPlanPreview(adjacentID)
            }
        } catch {
            Self.logger.error("도면 목록 삭제 실패: \(error.localizedDescription, privacy: .private)")
            floorPlanDeletionError = "도면을 목록에서 삭제하지 못했습니다. 잠시 후 다시 시도해주세요."
        }
    }

    func openFloorPlanCreation() {
        guard floorPlanCatalogState == .loaded else { return }
        floorPlanDraft.begin()
        phase = .floorPlanCreation
    }
    func openSessionCreation() {
        guard canOpenSessionCreation else { return }
        phase = .sessionCreation
    }
    func registerFloorPlan() {
        guard phase == .floorPlanCreation, !isUploadingFloorPlan,
              let registration = floorPlanDraft.registration(),
              let worldMapDraft = floorPlanDraft.worldMapScanDraft() else { return }
        uploadFloorPlan(registration, worldMapDraft: worldMapDraft)
    }
    func retryFloorPlanUpload() {
        guard (phase == .floorPlanCreation || phase == .floorPlanEditing),
              !isUploadingFloorPlan,
              let registration = failedFloorPlanRegistration else { return }
        let replacement = failedReplacementFloorPlanID.flatMap { id in
            floorPlans.first { $0.id == id }
        }
        uploadFloorPlan(registration, worldMapDraft: failedWorldMapDraft, replacing: replacement)
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
        cancelTrainingWork()
        stopObservingMembers()
        sessionCreationTask?.cancel()
        isCreatingSession = true
        sessionCreationError = nil
        sessionEndError = nil
        trainingStartedAt = nil
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
                    worldMap: floorPlan.worldMap,
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
        requestTrainingStart(with: participants)
    }
    func startTrainingExcludingUnreadyParticipants() {
        guard phase == .teamReadiness, canRequestTrainingStart else { return }
        requestTrainingStart(with: participants.filter(\.isReady))
    }
    func finishTraining() {
        guard canFinishTraining, let session = currentSession else { return }
        isFinishingTraining = true
        trainingActionError = nil
        let id = UUID()
        trainingActionID = id
        let repository = sessionRepository
        trainingActionTask = Task { [weak self] in
            do {
                try await repository.updateStatus(of: session, to: .ended)
                try Task.checkCancellation()
                guard let self, self.trainingActionID == id, self.phase == .trainingInProgress else { return }
                self.trainingActionTask = nil
                self.trainingActionID = nil
                self.isFinishingTraining = false
                self.enterResultsPreparation(for: session.id)
            } catch {
                guard !Task.isCancelled, let self, self.trainingActionID == id else { return }
                self.trainingActionTask = nil
                self.trainingActionID = nil
                self.isFinishingTraining = false
                self.trainingActionError = "훈련을 종료하지 못했습니다. 연결을 확인한 뒤 다시 종료해주세요."
            }
        }
    }

    func retrySessionObservation() {
        guard canRetrySessionObservation, let session = currentSession else { return }
        startObservingSession(id: session.id)
    }

    func retryRecordingObservation() {
        guard phase == .resultsPreparation else { return }
        trainingRecords.retry()
    }

    func excludeParticipantFromAAR(_ id: String) {
        guard phase == .resultsPreparation else { return }
        trainingRecords.excludeParticipant(id)
    }

    func proceedToAAR() {
        guard phase == .resultsPreparation, trainingRecords.canProceedToAAR else { return }
        enterAAR()
    }

    private func enterAAR() {
        guard phase == .resultsPreparation, trainingRecords.canProceedToAAR else { return }
        let eligibleIDs = trainingRecords.aarEligibleParticipantIDs
        guard !eligibleIDs.isEmpty else { return }
        trainingRecords.stop()
        resetAARPresentationState()
        aarParticipantIDs = eligibleIDs
        playbackPosition = 331
        phase = .aar
    }

    func openAARVideoScreen() {
        guard phase == .aar, canOpenAARVideoScreen else { return }
        aarScreen = .video
    }

    func showAARFloorPlan() {
        guard phase == .aar else { return }
        aarScreen = .floorPlan
    }

    func updateAARFloorPlanViewport(
        scale: CGFloat,
        translation: CGSize,
        layout: AARFloorPlanLayout,
        container: CGSize
    ) {
        guard phase == .aar else { return }
        aarFloorPlanViewport = AARFloorPlanViewport(
            scale: scale,
            translation: translation
        ).clamped(layout: layout, container: container)
    }

    func isParticipantSelected(_ id: String) -> Bool { selectedParticipantIDs.contains(id) }

    func videoSlotNumber(for participantID: String) -> Int? {
        selectedParticipantIDs.firstIndex(of: participantID).map { $0 + 1 }
    }

    func isParticipantMuted(_ id: String) -> Bool { !unmutedParticipantIDs.contains(id) }

    func toggleParticipantMute(_ id: String) {
        guard isParticipantSelected(id) else { return }
        if unmutedParticipantIDs.contains(id) {
            unmutedParticipantIDs.remove(id)
        } else {
            unmutedParticipantIDs.insert(id)
        }
    }
    func canToggleParticipant(_ id: String) -> Bool {
        phase == .aar && aarParticipantIDs.contains(id)
    }

    func toggleParticipantSelection(_ id: String) {
        guard canToggleParticipant(id) else { return }
        if let index = selectedParticipantIDs.firstIndex(of: id) {
            selectedParticipantIDs.remove(at: index)
            unmutedParticipantIDs.remove(id)
            if selectedParticipantIDs.isEmpty { aarScreen = .floorPlan }
        } else {
            selectedParticipantIDs.insert(id, at: 0)
            if selectedParticipantIDs.count > maximumVideoCount,
               let removedID = selectedParticipantIDs.popLast() {
                unmutedParticipantIDs.remove(removedID)
            }
        }
    }

    func setPlaybackPosition(_ value: Double) {
        guard value.isFinite else { return }
        playbackPosition = min(max(0, value), playbackDuration)
    }
    func finishAAR() {
        guard phase == .aar else { return }
        resetAARPresentationState()
        phase = .aarCompleted
    }
    func returnHome() {
        cancelSessionWork()
        trainingName = "샘플 훈련"
        selectFloorPlan(floorPlans.first?.id)
        participants = []
        resetAARPresentationState()
        currentSession = nil
        trainingStartedAt = nil
        playbackPosition = 331
        phase = .home
    }

    /// 화면 트리에서 Store를 제거하기 전에 진행 중인 앱 내부 작업을 모두 정리한다.
    func shutdown() {
        clearFloorPlanListPreview()
        cancelFloorPlanDetailLoad()
        clearFloorPlanUpload()
        floorPlanDraft.reset()
        returnHome()
    }

    func goBack() {
        guard !isUploadingFloorPlan, !isCreatingSession, !isEndingSession, !isStartingTraining else { return }
        switch phase {
        case .floorPlanList:
            clearFloorPlanListPreview()
            phase = .home
        case .floorPlanDetail:
            cancelFloorPlanDetailLoad()
            clearFloorPlanDetail()
            phase = .floorPlanList
        case .sessionCreation:
            cancelSessionCreation()
            phase = .home
        case .floorPlanCreation:
            clearFloorPlanUpload()
            if !floorPlanDraft.goBackCreationStep() {
                floorPlanDraft.reset()
                phase = .floorPlanList
            }
        case .floorPlanEditing:
            clearFloorPlanUpload()
            floorPlanDraft.reset()
            editingFloorPlanID = nil
            phase = .floorPlanDetail
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
        worldMap: WorldMapReference?,
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
                floorPlan: floorPlan,
                worldMap: worldMap
            )
            guard session.worldMapMatchesFloorPlan else {
                throw SessionCreationError.worldMapMismatch
            }
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
        cancelTrainingWork()
        cancelSessionCreation()
        stopObservingMembers()
        sessionEndTask?.cancel()
        sessionEndTask = nil
        isEndingSession = false
        sessionEndError = nil
    }

    private func requestTrainingStart(with candidates: [InstructorParticipant]) {
        guard let session = currentSession, !candidates.isEmpty else { return }
        stopObservingMembers()
        isStartingTraining = true
        trainingActionError = nil
        let id = UUID()
        trainingActionID = id
        let repository = sessionRepository
        trainingActionTask = Task { [weak self] in
            do {
                try await repository.updateStatus(of: session, to: .running)
                try Task.checkCancellation()
                guard let self, self.trainingActionID == id, self.phase == .teamReadiness else { return }
                self.trainingActionTask = nil
                self.trainingActionID = nil
                self.isStartingTraining = false
                self.trainingParticipants = candidates
                self.participants = candidates
                // 쓰기 성공은 확인했지만 시작 시각은 후속 서버 스냅샷으로만 채운다.
                self.trainingStartedAt = nil
                self.currentSession = Self.session(session, with: .running)
                self.phase = .trainingInProgress
                self.startObservingSession(id: session.id)
            } catch {
                guard !Task.isCancelled, let self, self.trainingActionID == id else { return }
                self.trainingActionTask = nil
                self.trainingActionID = nil
                self.isStartingTraining = false
                self.trainingActionError = "훈련을 시작하지 못했습니다. 연결을 확인한 뒤 다시 시작해주세요."
                self.startObservingMembers(for: session)
            }
        }
    }

    private func startObservingSession(id sessionID: UUID) {
        stopObservingSession()
        sessionConnectionState = .connecting
        let id = UUID()
        sessionObservationID = id
        let repository = sessionRepository
        sessionObservationTask = Task { [weak self] in
            do {
                for try await session in repository.observeSession(id: sessionID) {
                    try Task.checkCancellation()
                    guard let self, self.sessionObservationID == id,
                          self.currentSession?.id == sessionID, self.phase == .trainingInProgress else { return }
                    guard session.id == sessionID, session.status == .running || session.status == .ended else { continue }
                    self.currentSession = session
                    self.trainingStartedAt = session.startedAt
                    self.sessionConnectionState = .connected
                    // 종료 쓰기 중에는 보류 중인 로컬 스냅샷으로 화면을 먼저 전환하지 않는다.
                    if session.status == .ended, !self.isFinishingTraining {
                        self.enterResultsPreparation(for: sessionID)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
            }
            guard !Task.isCancelled, let self, self.sessionObservationID == id else { return }
            self.sessionObservationTask = nil
            self.sessionObservationID = nil
            self.sessionConnectionState = .failed
            self.sessionObservationError = "세션 상태 연결이 끊어졌습니다. 다시 연결해주세요."
        }
    }

    private func enterResultsPreparation(for sessionID: UUID) {
        guard phase == .trainingInProgress, let session = currentSession, session.id == sessionID else { return }
        currentSession = Self.session(session, with: .ended)
        stopObservingSession()
        trainingActionError = nil
        phase = .resultsPreparation
        trainingRecords.observe(sessionID: sessionID, participants: trainingParticipants) { [weak self] in
            guard let self, self.currentSession?.id == sessionID else { return }
            self.enterAAR()
        }
    }

    private func stopObservingSession() {
        sessionObservationID = nil
        sessionObservationTask?.cancel()
        sessionObservationTask = nil
        sessionConnectionState = .idle
        sessionObservationError = nil
    }

    private func cancelTrainingWork() {
        trainingActionID = nil
        trainingActionTask?.cancel()
        trainingActionTask = nil
        isStartingTraining = false
        isFinishingTraining = false
        trainingActionError = nil
        trainingParticipants = []
        stopObservingSession()
        trainingRecords.reset()
    }

    private static func session(_ session: Session, with status: SessionStatus) -> Session {
        Session(id: session.id, pin: session.pin, name: session.name, status: status,
                startedAt: session.startedAt, floorPlan: session.floorPlan)
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

#if DEBUG
    /// 에뮬레이터 시험 데이터(`scripts/seed-aar-emulator.py`)의 세션으로 AAR을 바로 연다.
    /// 훈련 시작·종료 흐름 없이 AAR 화면을 확인하기 위한 디버그 전용 진입점이다.
    func openAARForDebug(session: Session, members: [Member]) {
        cancelSessionWork()
        currentSession = session
        participants = Self.displayParticipants(from: members)
        if let plan = floorPlans.first(where: { $0.reference == session.floorPlan }) {
            selectFloorPlan(plan.id)
        }
        resetAARPresentationState()
        aarParticipantIDs = Set(participants.map(\.id))
        phase = .aar
    }
#endif

    private func resetAARPresentationState() {
        aarScreen = .floorPlan
        aarFloorPlanViewport = .identity
        aarParticipantIDs = []
        selectedParticipantIDs = []
        unmutedParticipantIDs = []
    }

    private func loadFloorPlanDetail(_ plan: InstructorFloorPlan) {
        floorPlanDetailTask?.cancel()
        let repository = floorPlanFileRepository
        floorPlanDetailTask = Task { [weak self] in
            do {
                let snapshot: LocalFloorPlanSnapshot
                if let registeredPlan = plan.registeredPlan {
                    let preparation = Task.detached(priority: .userInitiated) {
                        try LocalFloorPlanFileLoader.snapshot(from: registeredPlan)
                    }
                    snapshot = try await withTaskCancellationHandler {
                        try await preparation.value
                    } onCancel: { preparation.cancel() }
                } else {
                    let files = try await repository.download(plan.reference)
                    try Task.checkCancellation()
                    let preparation = Task.detached(priority: .userInitiated) {
                        try LocalFloorPlanFileLoader.load(
                            files: files,
                            reference: plan.reference,
                            catalog: plan
                        )
                    }
                    snapshot = try await withTaskCancellationHandler {
                        try await preparation.value
                    } onCancel: { preparation.cancel() }
                }
                try Task.checkCancellation()
                guard let self, self.phase == .floorPlanDetail,
                      self.viewedFloorPlanID == plan.id else { return }
                self.applyFloorPlanDetail(snapshot, for: plan.id)
                self.floorPlanDetailTask = nil
            } catch {
                guard let self, !(error is CancellationError),
                      self.phase == .floorPlanDetail,
                      self.viewedFloorPlanID == plan.id else { return }
                let failure = error as NSError
                Self.logger.error("도면 상세 복원 실패: domain=\(failure.domain, privacy: .public) code=\(failure.code) description=\(failure.localizedDescription, privacy: .private)")
                self.floorPlanDetailTask = nil
                self.floorPlanDetailState = .failed(
                    "도면 상세 정보를 불러오지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해주세요."
                )
            }
        }
    }

    private func loadFloorPlanListPreview(_ floorPlan: InstructorFloorPlan) {
        floorPlanListPreviewTask?.cancel()
        previewedFloorPlanID = floorPlan.id
        floorPlanListPreviewState = .loading
#if canImport(UIKit)
        floorPlanListPreviewImage = nil
        floorPlanListPreviewMaskImage = nil
#endif
        let loader = floorPlanListPreviewLoader
        let expectedReference = floorPlan.reference
        floorPlanListPreviewTask = Task { [weak self] in
            do {
                let snapshot = try await loader.load(floorPlan)
                try Task.checkCancellation()
                guard let self,
                      self.phase == .floorPlanList,
                      self.previewedFloorPlanID == floorPlan.id,
                      self.previewedFloorPlan?.reference == expectedReference else { return }
#if canImport(UIKit)
                guard let image = UIImage(data: snapshot.imagePNGData),
                      let mask = UIImage(
                        data: snapshot.maskPNGData,
                        scale: snapshot.maskScale
                      ) else {
                    self.floorPlanListPreviewState = .failed("도면 미리보기를 표시하지 못했습니다.")
                    self.floorPlanListPreviewTask = nil
                    return
                }
                self.floorPlanListPreviewImage = image
                self.floorPlanListPreviewMaskImage = mask
#endif
                self.floorPlanListPreviewState = .loaded
                self.floorPlanListPreviewTask = nil
            } catch {
                guard let self, !(error is CancellationError),
                      self.phase == .floorPlanList,
                      self.previewedFloorPlanID == floorPlan.id,
                      self.previewedFloorPlan?.reference == expectedReference else { return }
                Self.logger.error("도면 목록 미리보기 실패: \(error.localizedDescription, privacy: .private)")
                self.floorPlanListPreviewState = .failed(
                    "도면 미리보기를 불러오지 못했습니다. 연결을 확인한 뒤 다시 시도해주세요."
                )
                self.floorPlanListPreviewTask = nil
            }
        }
    }

    private func selectDefaultFloorPlanPreviewIfNeeded() {
        guard phase == .floorPlanList,
              floorPlanCatalogState == .loaded,
              previewedFloorPlanID == nil,
              let first = floorPlans.first else { return }
        loadFloorPlanListPreview(first)
    }

    private func clearFloorPlanListPreview() {
        floorPlanListPreviewTask?.cancel()
        floorPlanListPreviewTask = nil
        previewedFloorPlanID = nil
        floorPlanListPreviewState = .idle
#if canImport(UIKit)
        floorPlanListPreviewImage = nil
        floorPlanListPreviewMaskImage = nil
#endif
    }

    private func applyFloorPlanDetail(_ snapshot: LocalFloorPlanSnapshot, for id: String) {
        guard viewedFloorPlanID == id else { return }
#if canImport(UIKit)
        guard let image = UIImage(data: snapshot.registration.image.pngData),
              let mask = UIImage(
                data: snapshot.maskPNGData,
                scale: 1 / CGFloat(snapshot.registration.resolvedGrid.cellSizePixels)
              ) else {
            floorPlanDetailState = .failed("도면 미리보기를 표시하지 못했습니다.")
            return
        }
        floorPlanDetailImage = image
        floorPlanDetailMaskImage = mask
#endif
        floorPlanDetailSnapshot = snapshot
        floorPlanDetailState = .loaded
    }

    private func cancelFloorPlanDetailLoad() {
        floorPlanDetailTask?.cancel()
        floorPlanDetailTask = nil
    }

    private func clearFloorPlanDetail() {
        cancelFloorPlanDetailLoad()
        viewedFloorPlanID = nil
        floorPlanDetailSnapshot = nil
        floorPlanDetailState = .idle
        floorPlanDeletionError = nil
        editingFloorPlanID = nil
#if canImport(UIKit)
        floorPlanDetailImage = nil
        floorPlanDetailMaskImage = nil
#endif
    }

    private static func sessionCreationMessage(for error: Error) -> String {
        if error is SessionCreationError {
            return "도면과 공간 스캔 정보가 일치하지 않습니다. 도면을 다시 저장해주세요."
        }
        if error as? RepositoryError == .pinTaken {
            return "사용 가능한 PIN을 만들지 못했습니다. 다시 시도해주세요."
        }
        return "세션을 만들지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해주세요."
    }

    private func uploadFloorPlan(
        _ registration: LocalRegisteredFloorPlan,
        worldMapDraft: LocalWorldMapScanDraft? = nil,
        replacing existingPlan: InstructorFloorPlan? = nil
    ) {
        isUploadingFloorPlan = true
        floorPlanUploadError = nil
        failedFloorPlanRegistration = registration
        failedWorldMapDraft = worldMapDraft
        failedReplacementFloorPlanID = existingPlan?.id
        let repository = floorPlanFileRepository
        let worldMapRepository = worldMapFileRepository
        let catalogRepository = floorPlanCatalogRepository
        let expectedPhase: InstructorPhase = existingPlan == nil ? .floorPlanCreation : .floorPlanEditing
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
                let worldMapReference: WorldMapReference?
                if let worldMapDraft {
                    guard let worldMapRepository else {
                        throw LocalFloorPlanError.invalid("WorldMap 저장소가 구성되지 않았습니다.")
                    }
                    let worldMapUpload = try LocalWorldMapFileBuilder.build(
                        from: worldMapDraft,
                        floorPlan: upload.reference
                    )
                    try await worldMapRepository.upload(
                        worldMapUpload.files,
                        for: worldMapUpload.reference
                    )
                    worldMapReference = worldMapUpload.reference
                } else if let existingWorldMap = existingPlan?.worldMap {
                    guard let worldMapRepository else {
                        throw LocalFloorPlanError.invalid("WorldMap 저장소가 구성되지 않았습니다.")
                    }
                    let existingFiles = try await worldMapRepository.download(existingWorldMap)
                    try Task.checkCancellation()
                    let rebound = try LocalWorldMapFileBuilder.rebind(
                        existingFiles,
                        from: existingWorldMap,
                        to: upload.reference
                    )
                    try await worldMapRepository.upload(rebound.files, for: rebound.reference)
                    worldMapReference = rebound.reference
                } else {
                    worldMapReference = nil
                }
                try Task.checkCancellation()
                let now = Date.now
                let plan = InstructorFloorPlan(
                    id: existingPlan?.id ?? upload.registration.id.uuidString,
                    name: existingPlan?.name ?? upload.registration.name,
                    fileName: existingPlan?.fileName ?? upload.registration.image.fileName,
                    referenceDistance: existingPlan?.referenceDistance ?? upload.registration.scale.meters,
                    reference: upload.reference,
                    worldMap: worldMapReference,
                    createdAt: existingPlan?.createdAt ?? now,
                    updatedAt: now,
                    registeredPlan: upload.registration
                )
                do {
                    try catalogRepository.save(plan)
                } catch {
                    let failure = error as NSError
                    Self.logger.error("등록 도면 로컬 저장 실패: domain=\(failure.domain, privacy: .public) code=\(failure.code) description=\(failure.localizedDescription, privacy: .private)")
                    throw FloorPlanRegistrationError.localSave
                }
                try Task.checkCancellation()
                guard let self, self.phase == expectedPhase else { return }
                if let index = self.floorPlans.firstIndex(where: { $0.id == plan.id }) {
                    self.floorPlans[index] = plan
                } else {
                    self.floorPlans.append(plan)
                }
                if self.previewedFloorPlanID == plan.id {
                    self.clearFloorPlanListPreview()
                }
                self.floorPlans.sort { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
                self.floorPlanCatalogState = .loaded
                self.selectFloorPlan(plan.id)
                let detailSnapshot = self.floorPlanDraft.maskPNGData.map {
                    LocalFloorPlanSnapshot(registration: upload.registration, maskPNGData: $0)
                }
                self.clearFloorPlanUpload()
                self.floorPlanDraft.reset()
                if let detailSnapshot, existingPlan != nil {
                    self.viewedFloorPlanID = plan.id
                    self.editingFloorPlanID = nil
                    self.applyFloorPlanDetail(detailSnapshot, for: plan.id)
                    self.phase = .floorPlanDetail
                } else {
                    self.phase = .floorPlanList
                }
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
        failedWorldMapDraft = nil
        failedReplacementFloorPlanID = nil
    }

    private static func floorPlanUploadMessage(for error: Error) -> String {
        if error as? FloorPlanRegistrationError == .localSave {
            return "도면 파일은 업로드했지만 기기에 목록을 저장하지 못했습니다. 다시 시도해주세요."
        }
        return switch error as? RepositoryError {
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
