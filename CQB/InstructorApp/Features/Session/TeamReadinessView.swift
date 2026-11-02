import CQBCore
import CQBDesignSystem
import SwiftUI

struct TeamReadinessView: View {
    @Environment(InstructorStore.self) private var store
    @State private var isShowingExclusionConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navigationBar
                .padding(.horizontal, DSSpacing.s40)
                .padding(.top, DSSpacing.s40)

            Text("팀 준비 상태")
                .dsTextStyle(DSTypography.headingBold36)
                .foregroundStyle(DSColor.contentPrimary)
                .padding(.horizontal, DSSpacing.s40)
                .padding(.top, 100)
                .padding(.bottom, DSSpacing.s20)

            readinessContent
                .padding(.horizontal, DSSpacing.s40)
                .padding(.bottom, DSSpacing.s60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.backgroundPrimary)
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

    private var navigationBar: some View {
        HStack(spacing: 0) {
            FloorPlanBackButton(action: store.goBack)
                .disabled(!store.canGoBack)

            Spacer()

            Button(action: requestTrainingStart) {
                Text("훈련 시작")
                    .padding(.vertical, DSSpacing.s12)
            }
            .buttonStyle(.dsPrimary)
            .frame(width: 180)
            .disabled(!store.canRequestTrainingStart)
            .accessibilityIdentifier("readiness.start")
        }
        .frame(height: DSSize.controlHeight)
    }

    private var readinessContent: some View {
        GeometryReader { proxy in
            let innerWidth = max(0, proxy.size.width - 20)
            let columnGap: CGFloat = innerWidth >= 1_266 ? 60 : 40
            let instructionWidth = min(320, max(280, innerWidth * 0.26))

            HStack(alignment: .top, spacing: columnGap) {
                readinessColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, DSSpacing.s16)

                joinInstructions
                    .frame(width: instructionWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 2)
            }
            .padding(.leading, DSSpacing.s8)
            .padding(.trailing, DSSpacing.s12)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.backgroundElevated)
        .clipShape(.rect(cornerRadius: DSRadius.large))
    }

    private var readinessColumn: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s12) {
            readinessHeader

            if store.participants.isEmpty {
                ContentUnavailableView(
                    "참가자가 없습니다",
                    systemImage: "person.3",
                    description: Text("대원이 세션에 참가하면 준비 상태가 표시됩니다.")
                )
                .foregroundStyle(DSColor.contentSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DSSpacing.s12) {
                        ForEach(store.participants) { participant in
                            ParticipantReadyRow(participant: participant)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var readinessHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 35) {
                Text("No.")
                Text("대원명")
            }

            Spacer()

            Text("준비 상태")
                .frame(width: 124, alignment: .leading)
        }
        .dsTextStyle(DSTypography.headingSemiBold20)
        .foregroundStyle(DSColor.contentPrimary)
        .padding(.horizontal, DSSpacing.s20)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .accessibilityElement(children: .combine)
    }

    private var joinInstructions: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("PIN")
                    .dsTextStyle(InstructorTypography.bodyMedium20)
                    .foregroundStyle(DSPalette.Gray.g200)

                Text(formattedPIN)
                    .dsTextStyle(DSTypography.displaySemiBold48)
                    .foregroundStyle(DSColor.contentPrimary)
                    .monospacedDigit()
                    .padding(.top, DSSpacing.s8)
                    .accessibilityLabel("세션 PIN \(store.currentSession?.pin ?? "없음")")
            }
            .padding(.top, DSSpacing.s40)
            .padding(.horizontal, DSSpacing.s24)

            Text("대원 기기에서 PIN을 입력해 훈련에 참가할 수 있습니다.")
                .dsTextStyle(DSTypography.bodyRegular12)
                .foregroundStyle(DSColor.contentSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, DSSpacing.s32)
                .padding(.leading, 29)
                .padding(.trailing, DSSpacing.s20)

            Rectangle()
                .fill(DSColor.surfaceSecondary)
                .frame(height: 1)
                .padding(.horizontal, DSSpacing.s20)
                .padding(.top, DSSpacing.s24)

            Text("대원 준비 완료")
                .dsTextStyle(DSTypography.captionRegular14)
                .foregroundStyle(DSColor.contentSecondary)
                .padding(.top, 19)
                .padding(.horizontal, DSSpacing.s24)

            Text("\(store.readyCount) / \(store.participants.count)")
                .dsTextStyle(DSTypography.displaySemiBold48)
                .foregroundStyle(DSColor.contentPrimary)
                .monospacedDigit()
                .padding(.top, DSSpacing.s32)
                .padding(.horizontal, DSSpacing.s24)
                .accessibilityLabel("전체 \(store.participants.count)명 중 \(store.readyCount)명 준비 완료")

            Spacer(minLength: DSSpacing.s20)

            readinessNotice
                .padding(.horizontal, DSSpacing.s20)
                .padding(.bottom, DSSpacing.s40)
        }
        .background(DSColor.surfacePrimary)
        .clipShape(.rect(cornerRadius: DSRadius.large))
    }

    private var readinessNotice: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s8) {
            Text(noticeTitle)
                .dsTextStyle(DSTypography.captionMedium14)
                .foregroundStyle(DSColor.contentPrimary)

            HStack(alignment: .bottom, spacing: DSSpacing.s8) {
                Text(noticeDescription)
                    .dsTextStyle(InstructorTypography.captionRegular13)
                    .foregroundStyle(DSColor.contentSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if store.memberConnectionState == .failed {
                    Spacer(minLength: 0)
                    Button("다시 연결", action: store.retryMemberObservation)
                        .dsTextStyle(DSTypography.bodyRegular12)
                        .foregroundStyle(DSColor.actionPrimary)
                        .buttonStyle(.plain)
                        .disabled(!store.canRetryMemberObservation)
                        .accessibilityIdentifier("readiness.reconnect")
                }
            }
        }
        .padding(DSSpacing.s16)
        .frame(maxWidth: .infinity, minHeight: 101, alignment: .topLeading)
        .background(DSColor.surfacePrimary)
        .clipShape(.rect(cornerRadius: DSRadius.medium))
    }

    private var formattedPIN: String {
        let pin = store.currentSession?.pin ?? "------"
        return pin.map(String.init).joined(separator: " ")
    }

    private var noticeTitle: String {
        if store.isStartingTraining { return "훈련을 시작하고 있습니다" }
        if store.isEndingSession { return "세션을 종료하고 있습니다" }
        if store.memberConnectionState == .connecting { return "준비 상태를 연결하고 있습니다" }
        if store.memberConnectionState == .failed { return "준비 상태를 불러오지 못했습니다" }
        if store.sessionEndError != nil || store.trainingActionError != nil { return "요청을 처리하지 못했습니다" }
        return "준비 상태를 확인해주세요"
    }

    private var noticeDescription: String {
        if let error = store.memberObservationError { return error }
        if let error = store.sessionEndError { return error }
        if let error = store.trainingActionError { return error }
        if store.isStartingTraining { return "준비된 대원으로 훈련을 시작합니다." }
        if store.isEndingSession { return "현재 세션을 안전하게 종료하고 있습니다." }
        if store.memberConnectionState == .connecting { return "대원 기기의 참가 상태를 확인하고 있습니다." }
        return "모든 대원이 설정을 마치면 훈련을 시작할 수 있습니다."
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
    let plan = InstructorFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    )
    var participants = InstructorPreviewFixture.participants
    for index in participants.indices { participants[index].isReady = index < 4 }
    participants.append(contentsOf: [
        InstructorParticipant(id: "member-7", number: 7, name: "새미", isReady: false, x: 0, y: 0),
        InstructorParticipant(id: "member-8", number: 8, name: "노을", isReady: false, x: 0, y: 0)
    ])
    let store = InstructorStore(
        floorPlans: [plan],
        previewSession: InstructorPreviewFixture.session(floorPlan: plan.reference, pin: "123456"),
        previewParticipants: participants
    )

    return TeamReadinessView()
        .environment(store)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
