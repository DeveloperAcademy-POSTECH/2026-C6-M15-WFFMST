import CQBCore
import CQBDesignSystem
import SwiftUI

/// 홈 화면이 표시하는 훈련 기록의 UI 전용 요약입니다.
/// 모든 기록을 최신순으로 보여주고, 직전 기록만 썸네일이 있는 큰 카드로 그립니다.
struct HomeTrainingRecordSummary: Identifiable {
    let id: UUID
    let title: String
    let floorPlanName: String
    let dateText: String
    let participantText: String
    let thumbnail: UIImage?
    let isOpening: Bool
}

struct HomeView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(InstructorDemoMode.self) private var demoMode

    private var trainingRecords: [HomeTrainingRecordSummary] {
        store.trainingHistory.enumerated().map { index, record in
            HomeTrainingRecordSummary(
                id: record.sessionID,
                title: record.trainingName,
                floorPlanName: record.floorPlanName,
                dateText: record.startedAtText,
                participantText: record.participantSummary,
                thumbnail: index == 0 ? store.trainingHistoryThumbnail(for: record) : nil,
                isOpening: store.openingTrainingHistorySessionID == record.sessionID
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = DSSpacing.s60
            let verticalInset: CGFloat = 90
            let availableWidth = max(0, proxy.size.width - horizontalInset * 2)

            if proxy.size.width >= 1_024 {
                let contentWidth = availableWidth
                let contentHeight = max(0, proxy.size.height - verticalInset * 2)
                let columnsWidth = max(0, contentWidth - DSSpacing.s24)
                let historyWidth = columnsWidth * 735 / 1_222
                let sideWidth = columnsWidth - historyWidth
                let sideContentHeight = max(0, contentHeight - DSSpacing.s24)
                let sessionHeight = sideContentHeight * 558 / 808
                let floorPlanHeight = sideContentHeight - sessionHeight

                HStack(alignment: .top, spacing: DSSpacing.s24) {
                    trainingHistoryCard
                    .frame(width: historyWidth, height: contentHeight)

                    VStack(spacing: DSSpacing.s24) {
                        SessionStartCard(
                            isEnabled: store.canOpenSessionCreation,
                            showsDemoEntry: !demoMode.isActive,
                            onStart: store.openSessionCreation,
                            onStartDemo: demoMode.start
                        )
                        .frame(width: sideWidth, height: sessionHeight)

                        FloorPlanManagementCard(
                            floorPlanCount: store.floorPlans.count,
                            action: store.openFloorPlanList
                        )
                        .frame(width: sideWidth, height: floorPlanHeight)
                    }
                }
                .frame(width: contentWidth, height: contentHeight)
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, verticalInset)
            } else {
                ScrollView {
                    VStack(spacing: DSSpacing.s24) {
                        trainingHistoryCard
                        .frame(height: 832)

                        SessionStartCard(
                            isEnabled: store.canOpenSessionCreation,
                            showsDemoEntry: !demoMode.isActive,
                            onStart: store.openSessionCreation,
                            onStartDemo: demoMode.start
                        )
                        .frame(height: 558)

                        FloorPlanManagementCard(
                            floorPlanCount: store.floorPlans.count,
                            action: store.openFloorPlanList
                        )
                        .frame(height: 250)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, DSSpacing.s60)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            "기록을 열지 못했습니다",
            isPresented: Binding(
                get: { store.phase == .home && store.trainingHistoryOpenError != nil },
                set: { if !$0 { store.dismissTrainingHistoryOpenError() } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(store.trainingHistoryOpenError ?? "")
        }
    }

    private var trainingHistoryCard: some View {
        TrainingHistoryCard(
            records: trainingRecords,
            errorMessage: store.trainingHistoryError,
            isSelectionEnabled: store.canSelectTrainingHistoryRecord,
            onShowAll: store.openTrainingHistory,
            onRetry: store.retryTrainingHistoryLoad,
            onSelectRecord: store.openTrainingHistoryRecord
        )
    }
}

private struct TrainingHistoryCard: View {
    let records: [HomeTrainingRecordSummary]
    let errorMessage: String?
    let isSelectionEnabled: Bool
    let onShowAll: () -> Void
    let onRetry: () -> Void
    let onSelectRecord: (UUID) -> Void

    var body: some View {
        HomeCardSurface {
            VStack(spacing: 0) {
                HStack {
                    Text("이전 훈련 기록")
                        .dsTextStyle(DSTypography.headingBold32)
                        .foregroundStyle(DSPalette.Neutral.white)

                    Spacer()

                    Button("모두보기", action: onShowAll)
                        .dsTextStyle(DSTypography.bodyRegular24)
                        .foregroundStyle(DSPalette.Primary.p200)
                        .fixedSize()
                        .accessibilityHint("이전 훈련 기록 전체 목록으로 이동합니다.")
                        .accessibilityIdentifier("home.trainingHistory.showAll")
                }
                .padding(.horizontal, DSSpacing.s20)
                .padding(.top, DSSpacing.s24)
                .frame(height: 102, alignment: .top)

                if let errorMessage {
                    HomeTrainingHistoryErrorState(message: errorMessage, onRetry: onRetry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if records.isEmpty {
                    HomeTrainingHistoryEmptyState()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DSSpacing.s20) {
                            TrainingRecordButton(
                                record: records[0],
                                prominence: .featured,
                                action: onSelectRecord
                            )

                            ForEach(records.dropFirst()) { record in
                                TrainingRecordButton(
                                    record: record,
                                    prominence: .compact,
                                    action: onSelectRecord
                                )
                            }
                        }
                        .padding(.horizontal, DSSpacing.s12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .disabled(!isSelectionEnabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.trainingHistory")
    }
}

private struct HomeTrainingHistoryEmptyState: View {
    var body: some View {
        VStack(spacing: DSSpacing.s12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(DSColor.contentTertiary)

            Text("아직 이전 훈련 기록이 없습니다")
                .dsTextStyle(DSTypography.headingSemiBold20)
                .foregroundStyle(DSColor.contentPrimary)

            Text("훈련을 완료하면 최근 기록을 여기에서 확인할 수 있습니다.")
                .dsTextStyle(DSTypography.bodyRegular16)
                .foregroundStyle(DSColor.contentTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(DSSpacing.s24)
        .accessibilityIdentifier("home.trainingHistory.empty")
    }
}

private struct HomeTrainingHistoryErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.s12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(DSColor.contentTertiary)

            Text(message)
                .dsTextStyle(DSTypography.bodyRegular16)
                .foregroundStyle(DSColor.contentPrimary)
                .multilineTextAlignment(.center)

            Button("다시 불러오기", action: onRetry)
                .buttonStyle(.dsSecondary)
                .accessibilityIdentifier("home.trainingHistory.retry")
        }
        .padding(DSSpacing.s24)
        .accessibilityIdentifier("home.trainingHistory.error")
    }
}

private struct TrainingRecordButton: View {
    enum Prominence {
        case featured, compact
    }

    let record: HomeTrainingRecordSummary
    let prominence: Prominence
    let action: (UUID) -> Void

    var body: some View {
        Button { action(record.id) } label: {
            content
                .overlay {
                    if record.isOpening {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.4))
                            .clipShape(.rect(cornerRadius: DSRadius.large))
                            .accessibilityLabel("AAR 불러오는 중")
                    }
                }
        }
        .buttonStyle(HomeCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.title), \(record.floorPlanName), \(record.dateText), \(record.participantText)")
        .accessibilityHint("AAR 화면으로 이동합니다.")
        .accessibilityIdentifier("home.trainingHistory.record.\(record.id.uuidString)")
    }

    @ViewBuilder
    private var content: some View {
        switch prominence {
        case .featured:
            VStack(alignment: .leading, spacing: 0) {
                thumbnail
                    .frame(maxWidth: .infinity)
                    .frame(height: 330, alignment: .bottom)
                    .clipShape(.rect(cornerRadius: DSRadius.medium))
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                Text(record.title)
                    .dsTextStyle(DSTypography.headingSemiBold28)
                    .foregroundStyle(DSColor.contentPrimary)
                    .lineLimit(1)
                    .padding(.top, DSSpacing.s12)
                    .padding(.horizontal, DSSpacing.s24)

                Text(record.floorPlanName)
                    .dsTextStyle(DSTypography.bodyRegular20)
                    .foregroundStyle(DSPalette.Gray.g200)
                    .lineLimit(1)
                    .padding(.horizontal, DSSpacing.s24)

                metadata
                    .padding(.horizontal, DSSpacing.s24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 451, alignment: .topLeading)
            .background(DSColor.surfaceSecondary)
            .clipShape(.rect(cornerRadius: DSRadius.large))
            .overlay(alignment: .topLeading) {
                Text("직전 강평 다시 보기")
                    .dsTextStyle(DSTypography.bodyRegular12)
                    .foregroundStyle(DSColor.contentPrimary)
                    .padding(.horizontal, DSSpacing.s12)
                    .padding(.vertical, DSSpacing.s8)
                    .background(DSColor.surfacePrimary)
                    .clipShape(.capsule)
                    .padding(.leading, DSSpacing.s24)
                    .padding(.top, DSSpacing.s24)
            }

        case .compact:
            VStack(alignment: .leading, spacing: 0) {
                Text(record.title)
                    .dsTextStyle(DSTypography.headingSemiBold24)
                    .foregroundStyle(DSColor.contentPrimary)
                    .lineLimit(1)

                Spacer(minLength: DSSpacing.s8)

                Text(record.floorPlanName)
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(DSPalette.Gray.g200)
                    .lineLimit(1)

                metadata
                    .padding(.top, DSSpacing.s4)
            }
            .padding(.horizontal, DSSpacing.s24)
            .padding(.top, DSSpacing.s12)
            .padding(.bottom, DSSpacing.s12)
            .frame(maxWidth: .infinity)
            .frame(height: 127, alignment: .leading)
            .background(DSColor.surfaceSecondary)
            .clipShape(.rect(cornerRadius: DSRadius.large))
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnail = record.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 330, alignment: .bottom)
                .clipped()
        } else {
            Rectangle()
                .fill(DSColor.backgroundElevated)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(DSColor.contentTertiary)
                }
        }
    }

    private var metadata: some View {
        HStack(spacing: DSSpacing.s40) {
            Text(record.dateText)
            Text(record.participantText)
        }
        .dsTextStyle(prominence == .featured ? DSTypography.bodyRegular16 : DSTypography.bodyRegular12)
        .foregroundStyle(DSColor.contentPrimary)
        .lineLimit(1)
    }
}

private struct SessionStartCard: View {
    let isEnabled: Bool
    let showsDemoEntry: Bool
    let onStart: () -> Void
    let onStartDemo: () -> Void

    var body: some View {
        HomeCardSurface {
            ZStack {
                Image("HomeSessionBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text("훈련 세션 만들고\n대원들을 초대하세요")
                            .dsTextStyle(DSTypography.headingBold32)
                            .foregroundStyle(DSColor.contentPrimary)

                        Spacer()

                        if showsDemoEntry {
                            Button(action: onStartDemo) {
                                Label("데모 모드", systemImage: "testtube.2")
                                    .dsTextStyle(DSTypography.bodyRegular12)
                                    .foregroundStyle(DSColor.contentSecondary)
                                    .fixedSize()
                                    .padding(.horizontal, DSSpacing.s12)
                                    .padding(.vertical, DSSpacing.s8)
                                    .background(DSColor.surfaceSecondary)
                                    .clipShape(.capsule)
                            }
                            .buttonStyle(HomeCardButtonStyle())
                            .accessibilityHint("샘플 데이터로 전체 훈련 흐름을 체험합니다.")
                            .accessibilityIdentifier("home.demo")
                        }
                    }

                    Spacer()

                    HomeTrainingStartButton(
                        isEnabled: isEnabled,
                        action: onStart
                    )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityHint(
                            isEnabled
                                ? "훈련 세션 생성 화면으로 이동합니다."
                                : "도면을 등록한 후 사용할 수 있습니다."
                        )
                        .accessibilityIdentifier("home.createSession")
                }
                .padding(.horizontal, 28)
                .padding(.top, 52)
                .padding(.bottom, 43)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.sessionStart")
    }
}

private struct FloorPlanManagementCard: View {
    let floorPlanCount: Int
    let action: () -> Void

    var body: some View {
        HomeCardSurface {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s8) {
                        Text("도면 관리")
                            .dsTextStyle(DSTypography.headingBold32)
                            .foregroundStyle(DSColor.contentPrimary)

                        Spacer()

                        Text("준비된 도면")
                            .dsTextStyle(DSTypography.bodyRegular24)
                            .foregroundStyle(DSColor.contentPrimary)

                        Text("\(floorPlanCount)개")
                            .dsTextStyle(DSTypography.headingSemiBold24)
                            .foregroundStyle(DSPalette.Primary.p200)
                    }

                    Spacer()

                    Text("준비된 도면을 확인하거나\n새로운 훈련 도면을 등록할 수 있습니다.")
                        .dsTextStyle(DSTypography.bodyRegular16)
                        .foregroundStyle(DSColor.contentPrimary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, DSSpacing.s24)
                .padding(.top, DSSpacing.s24)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(HomeCardButtonStyle())
        }
        .accessibilityLabel("도면 관리, 준비된 도면 \(floorPlanCount)개")
        .accessibilityHint("등록된 도면 목록으로 이동합니다.")
        .accessibilityIdentifier("home.floorPlans")
    }

}

private struct HomeCardSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(DSColor.surfacePrimary)
                .clipShape(.rect(cornerRadius: DSRadius.large))
        }
    }
}

private struct HomeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("Figma · 최근 기록 있음") {
    let floorPlan = FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "preview")
    let records = (0..<3).map { index in
        TrainingHistoryRecord(
            sessionID: UUID(),
            trainingName: "A-3거점 진입 절차 동계 훈련",
            floorPlan: floorPlan,
            floorPlanName: "훈련장 A",
            participantNames: ["강유키"] + (1..<16).map { "대원 \($0)" },
            startedAt: Date(timeIntervalSince1970: 1_760_934_600 - Double(index) * 7_200),
            endedAt: Date(timeIntervalSince1970: 1_760_934_600 - Double(index) * 7_200 + 804)
        )
    }
    return NavigationStack {
        HomeView()
            .environment(InstructorStore(
                floorPlans: [
                    InstructorFloorPlan(
                        id: "preview-plan",
                        name: "훈련장 A",
                        fileName: "훈련장 A 도면.png",
                        referenceDistance: 15
                    )
                ],
                trainingHistory: records
            ))
            .environment(InstructorDemoMode())
    }
    .frame(width: 1_366, height: 1_024)
    .preferredColorScheme(.dark)
}

#Preview("기록과 등록 도면 없음") {
    NavigationStack {
        HomeView()
            .environment(InstructorStore(floorPlans: []))
            .environment(InstructorDemoMode())
    }
    .frame(width: 1_366, height: 1_024)
    .preferredColorScheme(.dark)
}
