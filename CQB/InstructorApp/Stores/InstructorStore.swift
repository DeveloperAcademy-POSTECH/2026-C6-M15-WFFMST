import CQBCore
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class InstructorStore {
    let floorPlanDraft: FloorPlanDraftStore
    @ObservationIgnored private let floorPlanFileRepository: any FloorPlanFileRepository
    @ObservationIgnored private var floorPlanUploadTask: Task<Void, Never>?
#if canImport(UIKit)
    private(set) var selectedPlanImage: UIImage?
#endif
    private(set) var phase: InstructorPhase = .home
    private(set) var floorPlans: [DemoFloorPlan]
    private(set) var trainingName = "샘플 훈련"
    private(set) var selectedFloorPlanID: String?
    private(set) var participants: [DemoParticipant] = []
    private(set) var readinessSample: ReadinessSample = .ready
    private(set) var aarMode: AARMode = .movement
    private(set) var selectedParticipantIDs: Set<String> = []
    private(set) var playbackPosition = 331.0
    private(set) var aarNotice: String?
    private(set) var isUploadingFloorPlan = false
    private(set) var floorPlanUploadError: String?
    private(set) var currentSession: Session?
    private var failedFloorPlanRegistration: LocalRegisteredFloorPlan?

    let invitationCode = "123456"
    let sampleTrainingElapsed = "00:12:34"
    let playbackDuration = 2172.0
    let maximumVideoCount = 4

    init(
        floorPlans: [DemoFloorPlan] = [],
        floorPlanDraft: FloorPlanDraftStore? = nil,
        floorPlanFileRepository: any FloorPlanFileRepository = DemoFloorPlanFileRepository()
    ) {
        self.floorPlanDraft = floorPlanDraft ?? FloorPlanDraftStore()
        self.floorPlanFileRepository = floorPlanFileRepository
        self.floorPlans = floorPlans
        selectedFloorPlanID = floorPlans.first?.id
    }

    var selectedFloorPlan: DemoFloorPlan? { floorPlans.first { $0.id == selectedFloorPlanID } }
    var canOpenSessionCreation: Bool { !floorPlans.isEmpty }
    var canCreateSession: Bool { !trainingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedFloorPlan != nil }
    var readyCount: Int { participants.filter(\.isReady).count }
    var unreadyCount: Int { participants.count - readyCount }
    var canStartTraining: Bool { !participants.isEmpty && participants.allSatisfy(\.isReady) }
    var canRequestTrainingStart: Bool { readyCount > 0 }
    var requiresUnreadyExclusionConfirmation: Bool { canRequestTrainingStart && unreadyCount > 0 }
    var canGoBack: Bool {
        [.floorPlanList, .floorPlanCreation, .sessionCreation, .teamReadiness].contains(phase)
            && !isUploadingFloorPlan
    }
    var selectedParticipants: [DemoParticipant] { participants.filter { selectedParticipantIDs.contains($0.id) } }
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
    func setTrainingName(_ value: String) { trainingName = value }
    func selectFloorPlan(_ id: String?) {
        guard id == nil || floorPlans.contains(where: { $0.id == id }) else { return }
        selectedFloorPlanID = id
#if canImport(UIKit)
        selectedPlanImage = selectedFloorPlan?.registeredPlan.flatMap { UIImage(data: $0.image.pngData) }
#endif
    }
    func createSession() {
        guard phase == .sessionCreation, canCreateSession, let floorPlan = selectedFloorPlan else { return }
        currentSession = Session(
            id: UUID(),
            pin: invitationCode,
            name: trainingName.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .preparing,
            floorPlan: floorPlan.reference
        )
        loadReadinessSample(.ready)
        phase = .teamReadiness
    }
    func loadReadinessSample(_ sample: ReadinessSample) {
        readinessSample = sample
        participants = sample == .empty ? [] : InstructorMockData.participants
        if sample == .partial {
            for index in participants.indices { participants[index].isReady = index < 3 }
        }
    }
    func startTraining() {
        guard phase == .teamReadiness, canStartTraining else { return }
        phase = .trainingInProgress
    }
    func startTrainingExcludingUnreadyParticipants() {
        guard phase == .teamReadiness, canRequestTrainingStart else { return }
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
        trainingName = "샘플 훈련"
        selectFloorPlan(floorPlans.first?.id)
        participants = []
        selectedParticipantIDs = []
        readinessSample = .ready
        aarMode = .movement
        aarNotice = nil
        currentSession = nil
        playbackPosition = 331
        phase = .home
    }
    func goBack() {
        guard !isUploadingFloorPlan else { return }
        switch phase {
        case .floorPlanList, .sessionCreation: phase = .home
        case .floorPlanCreation:
            clearFloorPlanUpload()
            if floorPlanDraft.step == .scaling {
                floorPlanDraft.returnToEditing()
            } else {
                floorPlanDraft.reset()
                phase = .floorPlanList
            }
        case .teamReadiness:
            participants = []
            currentSession = nil
            phase = .sessionCreation
        default: break
        }
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
