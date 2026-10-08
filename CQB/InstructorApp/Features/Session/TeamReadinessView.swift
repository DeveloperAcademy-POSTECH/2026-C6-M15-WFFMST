import SwiftUI

struct TeamReadinessView: View {
    @Environment(InstructorStore.self) private var store
    @State private var isShowingExclusionConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    sampleSelector
                    Spacer()
                    invitationCode
                }
                VStack(alignment: .leading, spacing: 12) {
                    invitationCode
                    sampleSelector
                }
            }

            HStack {
                Text("대원명")
                Spacer()
                Text("준비 상태 \(store.readyCount)/\(store.participants.count)")
                    .monospacedDigit()
            }
            .font(.headline)

            Divider()

            if store.participants.isEmpty {
                ContentUnavailableView("참가자가 없습니다", systemImage: "person.3", description: Text("위의 샘플 상태 메뉴에서 참가자가 있는 상태를 확인할 수 있습니다."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.participants) { participant in
                            participantRow(participant)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(24)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 24) {
                Text("미준비 대원이 있으면 확인 후 해당 대원을 제외하고 시작합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                ActionButton("훈련 시작") {
                    if store.requiresUnreadyExclusionConfirmation {
                        isShowingExclusionConfirmation = true
                    } else {
                        store.startTraining()
                    }
                }
                .disabled(!store.canRequestTrainingStart)
                .accessibilityIdentifier("readiness.start")
            }
            .padding(24)
            .background(.bar)
        }
        .alert("미준비 대원 제외", isPresented: $isShowingExclusionConfirmation) {
            Button("제외하고 시작", role: .destructive) {
                store.startTrainingExcludingUnreadyParticipants()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("설정이 준비되지 않은 대원 \(store.unreadyCount)명을 현재 세션에서 제외하고 훈련을 시작할까요?")
        }
    }

    private var sampleSelector: some View {
        Menu {
            ForEach(ReadinessSample.allCases) { sample in
                ActionButton(sample.title) {
                    store.loadReadinessSample(sample)
                }
            }
        } label: {
            Label("샘플 상태: \(store.readinessSample.title)", systemImage: "slider.horizontal.3")
        }
        .accessibilityIdentifier("readiness.samples")
    }

    private var invitationCode: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("PIN · \(store.invitationCode)")
                .font(.title2.bold())
                .monospacedDigit()
            Text("샘플 코드 · 실제 참가 불가")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func participantRow(_ participant: DemoParticipant) -> some View {
        HStack(spacing: 20) {
            Text(participant.number, format: .number.precision(.integerLength(2)))
                .font(.headline.monospacedDigit())
            Text(participant.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            Label(participant.isReady ? "준비 완료" : "설정 중", systemImage: participant.isReady ? "checkmark.circle" : "clock")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }
}

#Preview {
    let store = InstructorStore()
    store.openSessionCreation()
    store.createSession()
    store.loadReadinessSample(.partial)
    return TeamReadinessView()
        .environment(store)
}
