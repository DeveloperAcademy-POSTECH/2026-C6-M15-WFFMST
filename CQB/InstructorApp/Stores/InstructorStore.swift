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
    enum FloorPlanSavePresentationStage: Equatable {
        case saving
        case finishing

        var message: String {
            switch self {
            case .saving:
                "잠시만 기다려주세요."
            case .finishing:
                "마무리하고 있습니다."
            }
        }
    }

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

    enum TrainingHistoryState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private enum FloorPlanRegistrationError: Error, Equatable {
        case localSave
    }

    private enum SessionCreationError: Error {
        case worldMapMismatch
    }

    private enum TrainingHistoryOpenError: Error {
        case sessionNotFound
    }

    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "InstructorStore")
    private static let floorPlanSaveLogger = Logger(
        subsystem: "com.wffmst.cqb",
        category: "FloorPlanSave"
    )

    let floorPlanDraft: FloorPlanDraftStore
    let trainingRecords: TrainingRecordStore
    @ObservationIgnored private let floorPlanFileRepository: any FloorPlanFileRepository
    @ObservationIgnored private let worldMapFileRepository: (any WorldMapFileRepository)?
    @ObservationIgnored private let floorPlanListPreviewLoader: any FloorPlanListPreviewLoading
    @ObservationIgnored private let floorPlanCatalogRepository: any FloorPlanCatalogRepository
    @ObservationIgnored private let sessionRepository: any SessionRepository
    @ObservationIgnored private let memberRepository: any MemberRepository
    @ObservationIgnored private let trainingHistoryRepository: any TrainingHistoryRepository
    @ObservationIgnored private var trainingHistoryOpenTask: Task<Void, Never>?
    @ObservationIgnored private let pinGenerator: () -> String
    @ObservationIgnored private var floorPlanUploadTask: Task<Void, Never>?
    @ObservationIgnored private var floorPlanDetailTask: Task<Void, Never>?
    @ObservationIgnored private var floorPlanListPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var sessionFloorPlanPreviewTask: Task<Void, Never>?
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
    /// 도면 ID별 기록 썸네일. 화면을 그릴 때마다 도면 PNG를 다시 풀지 않도록 둔다.
    @ObservationIgnored private var trainingHistoryThumbnails: [UUID: UIImage] = [:]
#endif
    private(set) var phase: InstructorPhase = .home
    private(set) var floorPlans: [InstructorFloorPlan]
    private(set) var floorPlanCatalogState: FloorPlanCatalogState
    private(set) var floorPlanDetailState: FloorPlanDetailState = .idle
    private(set) var floorPlanListPreviewState: FloorPlanListPreviewState = .idle
    private(set) var sessionFloorPlanPreviewState: FloorPlanListPreviewState = .idle
    private(set) var viewedFloorPlanID: String?
    private(set) var previewedFloorPlanID: String?
    private(set) var floorPlanDeletionError: String?
    private(set) var trainingName = ""
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
    private(set) var floorPlanSavePresentationStage: FloorPlanSavePresentationStage?
    private(set) var floorPlanUploadError: String?
    private(set) var currentSession: Session?
    private(set) var isCreatingSession = false
    private(set) var sessionCreationError: String?
    private(set) var memberObservationError: String?
    private(set) var memberConnectionState: MemberConnectionState = .idle
    private(set) var isEndingSession = false
    private(set) var sessionEndError: String?
    private(set) var trainingStartedAt: Date?
    /// 서버 종료 성공을 앱이 확인한 시각. 결과 준비 중에는 이 시각으로 훈련 시간을 고정한다.
    private(set) var trainingEndedAt: Date?
    private(set) var isStartingTraining = false
    private(set) var isFinishingTraining = false
    private(set) var trainingActionError: String?
    private(set) var sessionConnectionState: MemberConnectionState = .idle
    private(set) var sessionObservationError: String?
    private(set) var trainingParticipants: [InstructorParticipant] = []
    /// 시작 시각 최신순
    private(set) var trainingHistory: [TrainingHistoryRecord] = []
    private(set) var trainingHistoryState: TrainingHistoryState = .idle
    /// AAR을 열려고 서버 기록을 받는 중인 기록
    private(set) var openingTrainingHistorySessionID: UUID?
    private(set) var trainingHistoryOpenError: String?
    private(set) var trainingHistoryDeletionError: String?
    /// 이전 훈련 기록에서 연 AAR이다. 닫으면 `AAR 종료` 화면 없이 홈으로 간다.
    private(set) var isReviewingTrainingHistory = false
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
        trainingHistoryRepository: (any TrainingHistoryRepository)? = nil,
        trainingHistory: [TrainingHistoryRecord] = [],
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
        self.trainingHistoryRepository = trainingHistoryRepository
            ?? InMemoryTrainingHistoryRepository(records: trainingHistory)
        self.trainingHistory = trainingHistory.sorted { $0.startedAt > $1.startedAt }
        self.trainingHistoryState = trainingHistory.isEmpty ? .idle : .loaded
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
    var canOpenSessionCreation: Bool { floorPlanCatalogState == .loaded }
    var canOpenPreviewedFloorPlanDetail: Bool {
        phase == .floorPlanList
            && floorPlanListPreviewState == .loaded
            && previewedFloorPlan != nil
    }
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
        [.trainingHistory, .floorPlanList, .floorPlanDetail, .floorPlanCreation, .floorPlanEditing,
         .sessionCreation, .teamReadiness].contains(phase)
            && !isUploadingFloorPlan && !isCreatingSession && !isEndingSession && !isStartingTraining
    }
    var canFinishTraining: Bool { phase == .trainingInProgress && !isFinishingTraining }
    var canRetrySessionObservation: Bool {
        phase == .trainingInProgress && sessionConnectionState == .failed && !isFinishingTraining
    }
    func trainingElapsed(at now: Date) -> String? {
        guard trainingStartedAt != nil else { return nil }
        return formattedTrainingElapsed(at: trainingEndedAt ?? now)
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
    var isLoadingTrainingHistory: Bool { trainingHistoryState == .loading }
    var trainingHistoryError: String? {
        guard case .failed(let message) = trainingHistoryState else { return nil }
        return message
    }
    /// AAR을 여는 중에는 다른 기록을 누를 수 없다.
    var canSelectTrainingHistoryRecord: Bool {
        (phase == .home || phase == .trainingHistory) && openingTrainingHistorySessionID == nil
    }

    func formattedTrainingElapsed(at date: Date) -> String {
        guard let trainingStartedAt else { return Self.formatTrainingElapsed(0) }
        return Self.formatTrainingElapsed(date.timeIntervalSince(trainingStartedAt))
    }

    nonisolated static func formatTrainingElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func openTrainingHistory() {
        guard phase == .home else { return }
        trainingHistoryOpenError = nil
        trainingHistoryDeletionError = nil
        phase = .trainingHistory
    }

    func loadTrainingHistory() {
        guard trainingHistoryState == .idle || trainingHistoryError != nil else { return }
        trainingHistoryState = .loading
        do {
            trainingHistory = try trainingHistoryRepository.fetchAll()
            trainingHistoryState = .loaded
        } catch {
            Self.logger.error("이전 훈련 기록 복원 실패: \(error.localizedDescription, privacy: .private)")
            trainingHistoryState = .failed("이전 훈련 기록을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.")
        }
    }

    func retryTrainingHistoryLoad() {
        guard trainingHistoryError != nil else { return }
        loadTrainingHistory()
    }

    /// 기록의 세션과 대원을 서버에서 받아 AAR을 연다. 영상과 동선은 AAR 화면이 받는다.
    func openTrainingHistoryRecord(_ sessionID: UUID) {
        guard canSelectTrainingHistoryRecord,
              trainingHistory.contains(where: { $0.sessionID == sessionID }) else { return }
        trainingHistoryOpenTask?.cancel()
        openingTrainingHistorySessionID = sessionID
        trainingHistoryOpenError = nil
        trainingHistoryDeletionError = nil
        let origin = phase
        let sessions = sessionRepository
        let members = memberRepository
        trainingHistoryOpenTask = Task { [weak self] in
            do {
                async let fetchedSession = sessions.observeSession(id: sessionID).firstValue()
                async let fetchedMembers = members.observeMembers(sessionID: sessionID).firstValue()
                guard let session = try await fetchedSession else { throw TrainingHistoryOpenError.sessionNotFound }
                let memberList = try await fetchedMembers ?? []
                try Task.checkCancellation()
                // 응답을 받으면 이 요청의 로딩 상태를 먼저 비운다. 그 사이 다른 화면으로 갔으면 AAR로 넘어가지 않는다.
                guard let self, self.openingTrainingHistorySessionID == sessionID else { return }
                self.finishTrainingHistoryOpen()
                guard self.phase == origin else { return }
                self.enterAAR(reviewing: session, members: memberList, fromHistory: true)
            } catch {
                guard let self, !(error is CancellationError),
                      self.openingTrainingHistorySessionID == sessionID else { return }
                let failure = error as NSError
                Self.logger.error("이전 훈련 AAR 열기 실패: domain=\(failure.domain, privacy: .public) code=\(failure.code) description=\(failure.localizedDescription, privacy: .private)")
                self.finishTrainingHistoryOpen()
                guard self.phase == origin else { return }
                self.trainingHistoryOpenError = error is TrainingHistoryOpenError
                    ? "서버에서 훈련 기록을 찾지 못했습니다."
                    : "훈련 기록을 불러오지 못했습니다. 연결을 확인한 뒤 다시 시도해주세요."
            }
        }
    }

    private func finishTrainingHistoryOpen() {
        trainingHistoryOpenTask = nil
        openingTrainingHistorySessionID = nil
    }

    func dismissTrainingHistoryOpenError() {
        trainingHistoryOpenError = nil
    }

    /// 기기 목록에서만 지운다. 서버 영상·기록은 남긴다(#126 임시 가정).
    func deleteTrainingHistoryRecord(_ sessionID: UUID) {
        guard phase == .trainingHistory, canSelectTrainingHistoryRecord,
              trainingHistory.contains(where: { $0.sessionID == sessionID }) else { return }
        trainingHistoryDeletionError = nil
        trainingHistoryOpenError = nil
        do {
            try trainingHistoryRepository.delete(sessionID: sessionID)
            trainingHistory.removeAll { $0.sessionID == sessionID }
        } catch {
            Self.logger.error("이전 훈련 기록 삭제 실패: \(error.localizedDescription, privacy: .private)")
            trainingHistoryDeletionError = "기록을 삭제하지 못했습니다. 잠시 후 다시 시도해주세요."
        }
    }

    func dismissTrainingHistoryDeletionError() {
        trainingHistoryDeletionError = nil
    }

#if canImport(UIKit)
    /// 기록한 훈련의 도면 이미지를 썸네일로 쓴다. 이 기기에 도면이 없으면 nil이다.
    func trainingHistoryThumbnail(for record: TrainingHistoryRecord) -> UIImage? {
        let floorPlanID = record.floorPlan.floorPlanID
        if let cached = trainingHistoryThumbnails[floorPlanID] { return cached }
        guard let plan = floorPlans.first(where: { $0.reference.floorPlanID == floorPlanID }),
              let registeredPlan = plan.registeredPlan,
              let image = UIImage(data: registeredPlan.image.pngData) else { return nil }
        let width: CGFloat = 640
        let height = width * image.size.height / max(image.size.width, 1)
        let thumbnail = image.preparingThumbnail(of: CGSize(width: width, height: height)) ?? image
        trainingHistoryThumbnails[floorPlanID] = thumbnail
        return thumbnail
    }
#endif
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

    func openPreviewedFloorPlanDetail() {
        guard canOpenPreviewedFloorPlanDetail,
              let floorPlan = previewedFloorPlan else { return }
        openFloorPlanDetail(floorPlan.id)
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
        selectFloorPlan(selectedFloorPlanID ?? floorPlans.first?.id)
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
        guard phase == .sessionCreation else { return }
        guard let floorPlan = selectedFloorPlan else {
            cancelSessionFloorPlanPreview()
            return
        }
#if canImport(UIKit)
        if selectedPlanImage != nil {
            sessionFloorPlanPreviewTask?.cancel()
            sessionFloorPlanPreviewTask = nil
            sessionFloorPlanPreviewState = .loaded
            return
        }
#endif
        loadSessionFloorPlanPreview(floorPlan)
    }

    func retrySessionFloorPlanPreview() {
        guard phase == .sessionCreation,
              case .failed = sessionFloorPlanPreviewState,
              let floorPlan = selectedFloorPlan else { return }
        loadSessionFloorPlanPreview(floorPlan)
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
        trainingEndedAt = nil
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
        if isReviewingTrainingHistory {
            returnHome()
            return
        }
        resetAARPresentationState()
        phase = .aarCompleted
    }
    func returnHome() {
        cancelSessionWork()
        cancelTrainingHistoryOpen()
        trainingName = ""
        selectFloorPlan(floorPlans.first?.id)
        participants = []
        resetAARPresentationState()
        currentSession = nil
        trainingStartedAt = nil
        trainingEndedAt = nil
        playbackPosition = 331
        isReviewingTrainingHistory = false
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
        case .trainingHistory:
            cancelTrainingHistoryOpen()
            trainingHistoryDeletionError = nil
            phase = .home
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
            floorPlanDraft.reset()
            phase = .floorPlanList
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

    func goBackFloorPlanCreationStep() {
        guard phase == .floorPlanCreation, !isUploadingFloorPlan else { return }
        clearFloorPlanUpload()
        _ = floorPlanDraft.goBackCreationStep()
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
        cancelSessionFloorPlanPreview()
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
                self.trainingEndedAt = nil
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
        let endedAt = Date.now
        trainingEndedAt = endedAt
        currentSession = Self.session(session, with: .ended)
        saveTrainingHistory(for: session, endedAt: endedAt)
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

    /// 훈련이 끝나 결과 준비로 넘어갈 때 목록용 기록을 남긴다. 저장에 실패해도 훈련 흐름은 막지 않는다.
    private func saveTrainingHistory(for session: Session, endedAt: Date) {
        let record = TrainingHistoryRecord(
            sessionID: session.id,
            trainingName: session.name,
            floorPlan: session.floorPlan,
            floorPlanName: floorPlans.first { $0.reference == session.floorPlan }?.name ?? "",
            participantNames: trainingParticipants.map(\.name),
            startedAt: trainingStartedAt ?? session.startedAt ?? endedAt,
            endedAt: endedAt
        )
        do {
            try trainingHistoryRepository.save(record)
        } catch {
            Self.logger.error("이전 훈련 기록 저장 실패: \(error.localizedDescription, privacy: .private)")
            return
        }
        trainingHistory.removeAll { $0.sessionID == record.sessionID }
        let index = trainingHistory.firstIndex { $0.startedAt < record.startedAt } ?? trainingHistory.endIndex
        trainingHistory.insert(record, at: index)
    }

    private func cancelTrainingHistoryOpen() {
        trainingHistoryOpenTask?.cancel()
        trainingHistoryOpenTask = nil
        openingTrainingHistorySessionID = nil
        trainingHistoryOpenError = nil
    }

    /// 훈련 흐름 없이 지난 세션으로 AAR을 연다. 기록에 있는 모든 대원을 재생 대상으로 둔다.
    private func enterAAR(reviewing session: Session, members: [Member], fromHistory: Bool) {
        cancelSessionWork()
        currentSession = session
        trainingStartedAt = session.startedAt
        participants = Self.displayParticipants(from: members)
        if let plan = floorPlans.first(where: { $0.reference == session.floorPlan }) {
            selectFloorPlan(plan.id)
        }
        resetAARPresentationState()
        aarParticipantIDs = Set(participants.map(\.id))
        isReviewingTrainingHistory = fromHistory
        phase = .aar
    }

#if DEBUG
    /// 에뮬레이터 시험 데이터(`scripts/seed-aar-emulator.py`)의 세션으로 AAR을 바로 연다.
    /// 훈련 시작·종료 흐름 없이 AAR 화면을 확인하기 위한 디버그 전용 진입점이다.
    func openAARForDebug(session: Session, members: [Member]) {
        enterAAR(reviewing: session, members: members, fromHistory: false)
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

    private func loadSessionFloorPlanPreview(_ floorPlan: InstructorFloorPlan) {
        sessionFloorPlanPreviewTask?.cancel()
        sessionFloorPlanPreviewState = .loading
#if canImport(UIKit)
        selectedPlanImage = nil
#endif
        let loader = floorPlanListPreviewLoader
        let expectedID = floorPlan.id
        let expectedReference = floorPlan.reference
        sessionFloorPlanPreviewTask = Task { [weak self] in
            do {
                let snapshot = try await loader.load(floorPlan)
                try Task.checkCancellation()
                guard let self,
                      self.phase == .sessionCreation,
                      self.selectedFloorPlanID == expectedID,
                      self.selectedFloorPlan?.reference == expectedReference else { return }
#if canImport(UIKit)
                guard let image = UIImage(data: snapshot.imagePNGData) else {
                    self.sessionFloorPlanPreviewState = .failed("도면 미리보기를 표시하지 못했습니다.")
                    self.sessionFloorPlanPreviewTask = nil
                    return
                }
                self.selectedPlanImage = image
#endif
                self.sessionFloorPlanPreviewState = .loaded
                self.sessionFloorPlanPreviewTask = nil
            } catch {
                guard let self, !(error is CancellationError),
                      self.phase == .sessionCreation,
                      self.selectedFloorPlanID == expectedID,
                      self.selectedFloorPlan?.reference == expectedReference else { return }
                Self.logger.error("세션 도면 미리보기 실패: \(error.localizedDescription, privacy: .private)")
                self.sessionFloorPlanPreviewState = .failed(
                    "도면 미리보기를 불러오지 못했습니다. 연결을 확인한 뒤 다시 시도해주세요."
                )
                self.sessionFloorPlanPreviewTask = nil
            }
        }
    }

    private func cancelSessionFloorPlanPreview() {
        sessionFloorPlanPreviewTask?.cancel()
        sessionFloorPlanPreviewTask = nil
        sessionFloorPlanPreviewState = .idle
    }

    private func loadFloorPlanListPreview(_ floorPlan: InstructorFloorPlan) {
        floorPlanListPreviewTask?.cancel()
        previewedFloorPlanID = floorPlan.id
        floorPlanListPreviewState = .loading
#if canImport(UIKit)
        floorPlanListPreviewImage = nil
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
                guard let image = UIImage(data: snapshot.imagePNGData) else {
                    self.floorPlanListPreviewState = .failed("도면 미리보기를 표시하지 못했습니다.")
                    self.floorPlanListPreviewTask = nil
                    return
                }
                self.floorPlanListPreviewImage = image
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
        let saveStarted = ContinuousClock.now
        let preparationStarted = ContinuousClock.now
        isUploadingFloorPlan = true
        floorPlanSavePresentationStage = .saving
        floorPlanUploadError = nil
        failedFloorPlanRegistration = registration
        failedWorldMapDraft = worldMapDraft
        failedReplacementFloorPlanID = existingPlan?.id
        let repository = floorPlanFileRepository
        let worldMapRepository = worldMapFileRepository
        let catalogRepository = floorPlanCatalogRepository
        let expectedPhase: InstructorPhase = existingPlan == nil ? .floorPlanCreation : .floorPlanEditing
        let preparation = Task.detached(priority: .userInitiated) {
            let upload = try LocalFloorPlanFileBuilder.build(from: registration)
            let worldMapUpload = try worldMapDraft.map {
                try LocalWorldMapFileBuilder.build(from: $0, floorPlan: upload.reference)
            }
            try Task.checkCancellation()
            return (upload, worldMapUpload)
        }
        floorPlanUploadTask = Task { [weak self] in
            var activeStage = "prepare.files"
            do {
                let (upload, preparedWorldMap) = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: {
                    preparation.cancel()
                }
                Self.logFloorPlanSaveDuration(activeStage, since: preparationStarted)
                try Task.checkCancellation()
                let worldMapUpload: LocalWorldMapUpload?
                if let preparedWorldMap {
                    guard worldMapRepository != nil else {
                        throw LocalFloorPlanError.invalid("WorldMap 저장소가 구성되지 않았습니다.")
                    }
                    worldMapUpload = preparedWorldMap
                } else if let existingWorldMap = existingPlan?.worldMap {
                    guard let worldMapRepository else {
                        throw LocalFloorPlanError.invalid("WorldMap 저장소가 구성되지 않았습니다.")
                    }
                    activeStage = "worldMap.downloadAndRebind"
                    let reboundStarted = ContinuousClock.now
                    let existingFiles = try await worldMapRepository.download(existingWorldMap)
                    try Task.checkCancellation()
                    let rebound = try LocalWorldMapFileBuilder.rebind(
                        existingFiles,
                        from: existingWorldMap,
                        to: upload.reference
                    )
                    Self.logFloorPlanSaveDuration(activeStage, since: reboundStarted)
                    worldMapUpload = rebound
                } else {
                    worldMapUpload = nil
                }
                Self.logFloorPlanSaveFileSizes(
                    floorPlan: upload.files,
                    worldMap: worldMapUpload?.files
                )
                // 두 파일 묶음의 크기 검증이 끝난 뒤 업로드를 시작한다.
                try Task.checkCancellation()
                activeStage = "remote.upload.parallel"
                async let floorPlanUpload: Void = Self.runFloorPlanSaveStage("floorPlan.upload") {
                    try await repository.upload(upload.files, for: upload.reference)
                }
                if let worldMapUpload, let worldMapRepository {
                    async let worldMapUploadResult: Void = Self.runFloorPlanSaveStage("worldMap.upload") {
                        try await worldMapRepository.upload(
                            worldMapUpload.files,
                            for: worldMapUpload.reference
                        )
                    }
                    _ = try await (floorPlanUpload, worldMapUploadResult)
                } else {
                    try await floorPlanUpload
                }
                let worldMapReference = worldMapUpload?.reference
                try Task.checkCancellation()
                self?.floorPlanSavePresentationStage = .finishing
                await Task.yield()
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
                    activeStage = "catalog.save"
                    let catalogSaveStarted = ContinuousClock.now
                    try catalogRepository.save(plan)
                    Self.logFloorPlanSaveDuration(activeStage, since: catalogSaveStarted)
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
                Self.logFloorPlanSaveDuration("save.total", since: saveStarted)
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
                let result = error is CancellationError ? "cancelled" : "failure"
                Self.logFloorPlanSaveFailure(
                    activeStage: activeStage,
                    since: saveStarted,
                    result: result
                )
                guard let self, !(error is CancellationError) else { return }
                self.isUploadingFloorPlan = false
                self.floorPlanSavePresentationStage = nil
                self.floorPlanUploadTask = nil
                self.floorPlanUploadError = Self.floorPlanUploadMessage(for: error)
            }
        }
    }

    private static func runFloorPlanSaveStage(
        _ stage: String,
        operation: () async throws -> Void
    ) async throws {
        let started = ContinuousClock.now
        do {
            try await operation()
            logFloorPlanSaveDuration(stage, since: started)
        } catch {
            let result = error is CancellationError ? "cancelled" : "failure"
            logFloorPlanSaveDuration(stage, since: started, result: result)
            throw error
        }
    }

    private static func logFloorPlanSaveDuration(
        _ stage: String,
        since start: ContinuousClock.Instant,
        result: String = "success"
    ) {
#if DEBUG
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000
            + Double(duration.attoseconds) / 1_000_000_000_000_000
        floorPlanSaveLogger.info(
            "event=floor-plan-save stage=\(stage, privacy: .public) result=\(result, privacy: .public) duration_ms=\(milliseconds, privacy: .public)"
        )
#endif
    }

    private static func logFloorPlanSaveFileSizes(
        floorPlan: FloorPlanFiles,
        worldMap: WorldMapFiles?
    ) {
#if DEBUG
        floorPlanSaveLogger.info(
            "event=floor-plan-save stage=file-sizes floor_image_bytes=\(floorPlan.imagePNG.count, privacy: .public) floor_mask_bytes=\(floorPlan.resolvedMask.count, privacy: .public) floor_navigation_bytes=\(floorPlan.navigationMapJSON.count, privacy: .public) world_map_archive_bytes=\(worldMap?.worldMapArchive.count ?? 0, privacy: .public) world_map_setup_bytes=\(worldMap?.setupJSON.count ?? 0, privacy: .public)"
        )
#endif
    }

    private static func logFloorPlanSaveFailure(
        activeStage: String,
        since start: ContinuousClock.Instant,
        result: String
    ) {
#if DEBUG
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000
            + Double(duration.attoseconds) / 1_000_000_000_000_000
        floorPlanSaveLogger.info(
            "event=floor-plan-save stage=save.total result=\(result, privacy: .public) active_stage=\(activeStage, privacy: .public) duration_ms=\(milliseconds, privacy: .public)"
        )
#endif
    }

    private func clearFloorPlanUpload() {
        floorPlanUploadTask?.cancel()
        floorPlanUploadTask = nil
        isUploadingFloorPlan = false
        floorPlanSavePresentationStage = nil
        floorPlanUploadError = nil
        failedFloorPlanRegistration = nil
        failedWorldMapDraft = nil
        failedReplacementFloorPlanID = nil
    }

    private static func floorPlanUploadMessage(for error: Error) -> String {
        if let sizeError = error as? LocalUploadFileSizeError {
            return sizeError.localizedDescription
        }
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
