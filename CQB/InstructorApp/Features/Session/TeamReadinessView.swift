import CQBDesignSystem
import SwiftUI

struct TeamReadinessView: View {
    @Environment(InstructorStore.self) private var store
    @State private var isShowingExclusionConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InstructorBackButton(action: store.goBack)

            HStack(alignment: .top) {
                Text("팀 준비 상태")
                    .font(DSTypography.h1)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .frame(height: 48, alignment: .leading)

                Spacer()

                invitationCode
            }
            .frame(height: 56, alignment: .top)

            readinessList
                .padding(.top, 42)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack {
                Spacer()
                ActionButton("훈련 시작", fillsWidth: true, action: requestTrainingStart)
                    .frame(width: 354, height: 52)
                    .disabled(!store.canRequestTrainingStart)
                    .accessibilityIdentifier("readiness.start")
            }
        }
        .padding(.top, 32)
        .padding(.horizontal, 48)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert("미준비 대원 제외", isPresented: $isShowingExclusionConfirmation) {
            Button("제외하고 시작", role: .destructive) {
                store.startTrainingExcludingUnreadyParticipants()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("설정이 준비되지 않은 대원 \(store.unreadyCount)명을 현재 세션에서 제외하고 훈련을 시작할까요?")
        }
    }

    private var invitationCode: some View {
        Text("PIN · \(store.invitationCode)")
            .font(DSTypography.h2)
            .foregroundStyle(InstructorColor.textPrimary)
            .monospacedDigit()
            .frame(width: 314, height: 56)
            .background(InstructorColor.surfaceBase)
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
            }
            .accessibilityLabel("세션 PIN \(store.invitationCode)")
    }

    private var readinessList: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                readinessHeader

                if store.participants.isEmpty {
                    ContentUnavailableView(
                        "참가자가 없습니다",
                        systemImage: "person.3",
                        description: Text("대원이 세션에 참가하면 준비 상태가 표시됩니다.")
                    )
                    .foregroundStyle(InstructorColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(store.participants) { participant in
                        ParticipantReadyRow(participant: participant)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var readinessHeader: some View {
        HStack(spacing: 32) {
            Text("대원명")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("준비상태")

            Text("\(store.readyCount)/\(store.participants.count)")
                .monospacedDigit()
        }
        .font(DSTypography.h3)
        .foregroundStyle(InstructorColor.textPrimary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
        .background(InstructorColor.surfaceRaised)
        .clipShape(.rect(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }

    private func requestTrainingStart() {
        if store.requiresUnreadyExclusionConfirmation {
            isShowingExclusionConfirmation = true
        } else {
            store.startTraining()
        }
    }
}

#Preview("팀 준비 상태 · 일부 준비") {
    let store = InstructorStore(floorPlans: [
        DemoFloorPlan(
            id: "preview-plan",
            name: "훈련장 A 도면",
            fileName: "훈련장 A 도면.png",
            referenceDistance: 15
        )
    ])
    store.openSessionCreation()
    store.createSession()
    store.loadReadinessSample(.partial)

    return TeamReadinessView()
        .environment(store)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
