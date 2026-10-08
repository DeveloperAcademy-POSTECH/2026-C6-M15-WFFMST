import SwiftUI

struct TrainingSessionCreateView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            TextField("훈련명", text: Binding(get: { store.trainingName }, set: store.setTrainingName))
            SingleSelectionMenu(title: "훈련 도면", options: store.floorPlans, selection: store.selectedFloorPlanID,
                                optionTitle: \.name, onSelect: store.selectFloorPlan)
            ActionButton("세션 생성", action: store.createSession).disabled(!store.canCreateSession)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

