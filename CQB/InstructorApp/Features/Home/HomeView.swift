import SwiftUI

struct HomeView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            ActionButton("도면 정보 관리", action: store.openFloorPlanList)
            ActionButton("훈련 세션 생성", action: store.openSessionCreation)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

