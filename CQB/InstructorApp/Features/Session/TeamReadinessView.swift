import SwiftUI

struct TeamReadinessView: View {
    @Environment(InstructorStore.self) private var store
    @State private var participantToExclude: DemoParticipant?

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
                Text("데모에서는 참가자가 1명 이상이고 전원 준비된 경우에만 시작합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                ActionButton("훈련 시작", action: store.startTraining)
                    .disabled(!store.canStartTraining)
                    .accessibilityIdentifier("readiness.start")
            }
            .padding(24)
            .background(.bar)
        }
        .alert("샘플 목록에서 제외", isPresented: Binding(
            get: { participantToExclude != nil },
            set: { if !$0 { participantToExclude = nil } }
        ), presenting: participantToExclude) { participant in
            Button("제외", role: .destructive) {
                store.excludeParticipant(participant.id)
            }
            Button("취소", role: .cancel) {
                participantToExclude = nil
            }
        } message: { participant in
            Text("\(participant.displayName) · \(participant.name)을 현재 샘플 목록에서만 제외합니다. 실제 참가 취소나 기록 제외 처리는 하지 않으며, 훈련은 자동으로 시작되지 않습니다.")
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
            ActionButton("샘플에서 제외", systemImage: "person.crop.circle.badge.minus") {
                participantToExclude = participant
            }
            .accessibilityIdentifier("readiness.exclude.\(participant.id)")
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
