import Foundation
import Observation

@MainActor
@Observable
final class InstructorStore {
    private(set) var phase: InstructorPhase = .home
    private(set) var floorPlans: [DemoFloorPlan]
    private(set) var floorPlanDraftName = ""
    private(set) var hasSampleFloorPlan = false
    private(set) var trainingName = "샘플 훈련"
    private(set) var selectedFloorPlanID: String?
    private(set) var participants: [DemoParticipant] = []
    private(set) var readinessSample: ReadinessSample = .ready
    private(set) var aarMode: AARMode = .movement
    private(set) var selectedParticipantIDs: Set<String> = []
    private(set) var playbackPosition = 331.0
    private(set) var aarNotice: String?

    let invitationCode = "123456"
    let sampleTrainingElapsed = "00:12:34"
    let playbackDuration = 2172.0
    let maximumVideoCount = 4

    init(floorPlans: [DemoFloorPlan]? = nil) {
        let plans = floorPlans ?? InstructorMockData.floorPlans
        self.floorPlans = plans
        selectedFloorPlanID = plans.first?.id
    }

    var selectedFloorPlan: DemoFloorPlan? { floorPlans.first { $0.id == selectedFloorPlanID } }
    var canSaveFloorPlan: Bool { !floorPlanDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasSampleFloorPlan }
    var canCreateSession: Bool { !trainingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedFloorPlan != nil }
    var readyCount: Int { participants.filter(\.isReady).count }
    var unreadyCount: Int { participants.count - readyCount }
    var canStartTraining: Bool { !participants.isEmpty && participants.allSatisfy(\.isReady) }
    var canRequestTrainingStart: Bool { readyCount > 0 }
    var requiresUnreadyExclusionConfirmation: Bool { canRequestTrainingStart && unreadyCount > 0 }
    var canGoBack: Bool {
        [.floorPlanList, .floorPlanCreation, .sessionCreation, .teamReadiness].contains(phase)
    }
    var selectedParticipants: [DemoParticipant] { participants.filter { selectedParticipantIDs.contains($0.id) } }
    var selectionSummary: String {
        if selectedParticipantIDs.count == participants.count && !participants.isEmpty { return "전체 대원" }
        return selectedParticipants.isEmpty ? "대원 선택" : "대원 " + selectedParticipants.map { String($0.number) }.joined(separator: ", ")
    }
    var canSelectAllParticipants: Bool { aarMode == .movement || participants.count <= maximumVideoCount }

    func openFloorPlanList() { phase = .floorPlanList }
    func openFloorPlanCreation() {
        floorPlanDraftName = ""
        hasSampleFloorPlan = false
        phase = .floorPlanCreation
    }
    func setFloorPlanDraftName(_ value: String) { floorPlanDraftName = value }
    func useSampleFloorPlan() { hasSampleFloorPlan = true }
    func saveFloorPlan() {
        guard phase == .floorPlanCreation, canSaveFloorPlan else { return }
        let plan = DemoFloorPlan(id: UUID().uuidString,
                                 name: floorPlanDraftName.trimmingCharacters(in: .whitespacesAndNewlines),
                                 fileName: "샘플 도면.png", referenceDistance: 15)
        floorPlans.append(plan)
        if selectedFloorPlanID == nil { selectedFloorPlanID = plan.id }
        phase = .floorPlanList
    }
    func openSessionCreation() { phase = .sessionCreation }
    func setTrainingName(_ value: String) { trainingName = value }
    func selectFloorPlan(_ id: String?) {
        guard id == nil || floorPlans.contains(where: { $0.id == id }) else { return }
        selectedFloorPlanID = id
    }
    func createSession() {
        guard phase == .sessionCreation, canCreateSession else { return }
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
        selectedFloorPlanID = floorPlans.first?.id
        participants = []
        selectedParticipantIDs = []
        readinessSample = .ready
        aarMode = .movement
        aarNotice = nil
        playbackPosition = 331
        phase = .home
    }
    func goBack() {
        switch phase {
        case .floorPlanList, .sessionCreation: phase = .home
        case .floorPlanCreation: phase = .floorPlanList
        case .teamReadiness:
            participants = []
            phase = .sessionCreation
        default: break
        }
    }
}
