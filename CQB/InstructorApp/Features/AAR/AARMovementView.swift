import SwiftUI

struct AARMovementView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("동선 복기").font(.headline)

            if store.selectedParticipants.isEmpty {
                ContentUnavailableView("표시할 대원을 선택하세요", systemImage: "person.crop.circle.badge.questionmark",
                                       description: Text("오른쪽 표시 대상 메뉴에서 대원을 선택할 수 있습니다."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FloorPlanPreview(title: store.selectedFloorPlan?.name ?? "샘플 훈련 도면")
                    .overlay {
                        GeometryReader { geometry in
                            ForEach(store.selectedParticipants) { participant in
                                Text("\(participant.number)")
                                    .font(.headline.monospacedDigit())
                                    .frame(width: 36, height: 36)
                                    .background(.regularMaterial, in: Circle())
                                    .overlay(Circle().stroke(.primary))
                                    .position(x: geometry.size.width * participant.x,
                                              y: geometry.size.height * participant.y)
                                    .accessibilityLabel("\(participant.displayName) 샘플 위치")
                            }
                        }
                    }
                    .accessibilityIdentifier("aar.movement")
            }

            Text("고정 샘플 위치 · 실제 이동 기록이 아닙니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let store = InstructorStore()
    store.openSessionCreation()
    store.createSession()
    store.startTraining()
    store.finishTraining()
    return AARMovementView().environment(store)
}
