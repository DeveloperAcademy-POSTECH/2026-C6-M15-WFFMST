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
    private(set) var selectedMovementIDs: Set<String> = []
    private(set) var selectedVideoIDs: Set<String> = []
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
    var canStartTraining: Bool { !participants.isEmpty && participants.allSatisfy(\.isReady) }
    var canGoBack: Bool {
        [.floorPlanList, .floorPlanCreation, .sessionCreation, .teamReadiness].contains(phase)
    }
    var selectedParticipantIDs: Set<String> { aarMode == .movement ? selectedMovementIDs : selectedVideoIDs }
    var selectedParticipants: [DemoParticipant] { participants.filter { selectedParticipantIDs.contains($0.id) } }
    var selectionSummary: String {
        if selectedParticipantIDs.count == participants.count && !participants.isEmpty { return "전체 대원" }
        return selectedParticipants.isEmpty ? "대원 선택" : "대원 " + selectedParticipants.map { String($0.number) }.joined(separator: ", ")
    }
    var allParticipantsSelected: Bool { !participants.isEmpty && selectedParticipantIDs.count == participants.count }
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
    // 화면 검증용 목록 제외이며 실제 참가 취소·기록 제외 정책을 의미하지 않는다.
    func excludeParticipant(_ id: String) {
        guard phase == .teamReadiness else { return }
        participants.removeAll { $0.id == id }
    }
    func startTraining() {
        guard phase == .teamReadiness, canStartTraining else { return }
        phase = .trainingInProgress
    }
    func finishTraining() {
        guard phase == .trainingInProgress else { return }
        aarMode = .movement
        selectedMovementIDs = Set(participants.map(\.id))
        selectedVideoIDs = Set(participants.prefix(maximumVideoCount).map(\.id))
        playbackPosition = 331
        aarNotice = nil
        phase = .aar
    }
    // 데모에서는 동선/영상 선택을 따로 보관한다. 실제 제품의 전환 정책은 추후 합의한다.
    func changeAARMode(to mode: AARMode) {
        aarMode = mode
        aarNotice = nil
    }
    func isParticipantSelected(_ id: String) -> Bool { selectedParticipantIDs.contains(id) }
    func canToggleParticipant(_ id: String) -> Bool {
        guard participants.contains(where: { $0.id == id }) else { return false }
        return aarMode == .movement || selectedVideoIDs.contains(id) || selectedVideoIDs.count < maximumVideoCount
    }
    func toggleParticipantSelection(_ id: String) {
        guard canToggleParticipant(id) else {
            aarNotice = "영상은 최대 \(maximumVideoCount)명까지 선택할 수 있습니다."
            return
        }
        var selection = selectedParticipantIDs
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        if aarMode == .movement { selectedMovementIDs = selection } else { selectedVideoIDs = selection }
        aarNotice = nil
    }
    func selectAllParticipants() {
        guard canSelectAllParticipants else { return }
        if aarMode == .movement { selectedMovementIDs = Set(participants.map(\.id)) }
        else { selectedVideoIDs = Set(participants.map(\.id)) }
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
        selectedMovementIDs = []
        selectedVideoIDs = []
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
