import CQBCore
import CQBDesignSystem
import SwiftUI

/// 이전 훈련 기록 전체 목록. 기록을 누르면 AAR을 다시 열고, `삭제`로 서버 영상과 기기 목록에서 지운다.
struct TrainingHistoryView: View {
    @Environment(InstructorStore.self) private var store
    @State private var pendingDeletion: TrainingHistoryRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InstructorBackButton(action: store.goBack)
                .padding(.bottom, 111)

            Text("이전 훈련 기록")
                .dsTextStyle(DSTypography.headingBold36)
                .foregroundStyle(DSPalette.Neutral.white)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, DSSpacing.s12)

            content
        }
        .padding(.top, DSSpacing.s40)
        .padding(.horizontal, DSSpacing.s40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            pendingDeletion.map { "‘\($0.trainingName)’ 기록을 삭제하시겠습니까?" } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { record in
            Button("기록 삭제", role: .destructive) { store.deleteTrainingHistoryRecord(record.sessionID) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("삭제한 훈련 기록을 되돌릴 수 없습니다.")
        }
        .alert(
            "기록을 열지 못했습니다",
            isPresented: Binding(
                get: { store.trainingHistoryOpenError != nil },
                set: { if !$0 { store.dismissTrainingHistoryOpenError() } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(store.trainingHistoryOpenError ?? "")
        }
        .alert(
            "기록을 삭제하지 못했습니다",
            isPresented: Binding(
                get: { store.trainingHistoryDeletionError != nil },
                set: { if !$0 { store.dismissTrainingHistoryDeletionError() } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(store.trainingHistoryDeletionError ?? "")
        }
        .accessibilityIdentifier("trainingHistory")
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoadingTrainingHistory {
            status(title: "이전 훈련 기록을 불러오는 중입니다.", systemImage: "arrow.triangle.2.circlepath")
                .accessibilityIdentifier("trainingHistory.loading")
        } else if let error = store.trainingHistoryError {
            VStack(spacing: DSSpacing.s20) {
                status(title: error, systemImage: "exclamationmark.triangle")
                Button("다시 불러오기", action: store.retryTrainingHistoryLoad)
                    .buttonStyle(.dsSecondary)
                    .accessibilityIdentifier("trainingHistory.retry")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("trainingHistory.error")
        } else if store.trainingHistory.isEmpty {
            status(title: "아직 이전 훈련 기록이 없습니다", systemImage: "clock.arrow.circlepath")
                .accessibilityIdentifier("trainingHistory.empty")
        } else {
            ScrollView {
                LazyVStack(spacing: DSSpacing.s20) {
                    ForEach(store.trainingHistory) { record in
                        TrainingHistoryRow(
                            record: record,
                            isOpening: store.openingTrainingHistorySessionID == record.sessionID,
                            isDeleting: store.deletingTrainingHistorySessionID == record.sessionID,
                            isEnabled: store.canSelectTrainingHistoryRecord,
                            onOpen: { store.openTrainingHistoryRecord(record.sessionID) },
                            onDelete: { pendingDeletion = record }
                        )
                    }
                }
                .padding(.bottom, DSSpacing.s40)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func status(title: String, systemImage: String) -> some View {
        VStack(spacing: DSSpacing.s12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(DSColor.contentTertiary)

            Text(title)
                .dsTextStyle(DSTypography.headingSemiBold20)
                .foregroundStyle(DSColor.contentPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TrainingHistoryRow: View {
    @Environment(InstructorStore.self) private var store

    let record: TrainingHistoryRecord
    let isOpening: Bool
    let isDeleting: Bool
    let isEnabled: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: DSSpacing.s24) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: DSSpacing.s24) {
                        thumbnail
                            .frame(width: 323, height: 208)
                            .clipShape(.rect(cornerRadius: DSRadius.small))
                            .padding(.top, 1.5)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(record.trainingName)
                                .dsTextStyle(DSTypography.headingSemiBold32)
                                .foregroundStyle(DSPalette.Gray.g50)
                                .lineLimit(1)
                                .frame(height: 42, alignment: .leading)

                            Text(record.detailText)
                                .dsTextStyle(DSTypography.bodyRegular16)
                                .foregroundStyle(DSPalette.Gray.g100)
                                .lineLimit(1)
                                .padding(.top, DSSpacing.s4)

                            Spacer(minLength: DSSpacing.s12)

                            Text(record.durationText)
                                .dsTextStyle(DSTypography.bodyRegular24)
                                .foregroundStyle(DSPalette.Gray.g100)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 211)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(record.trainingName), \(record.detailText), 진행 시간 \(record.durationText)")
                .accessibilityHint("AAR 화면으로 이동합니다.")
                .accessibilityIdentifier("trainingHistory.record.\(record.sessionID.uuidString)")

                deleteButton
            }
            .padding(.top, DSSpacing.s20)
            .padding(.bottom, DSSpacing.s20)
            .disabled(!isEnabled)

            Rectangle()
                .fill(DSPalette.Gray.g400)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if isDeleting {
            ProgressView()
                .frame(width: 42, height: 42)
                .accessibilityLabel("삭제 중")
        } else {
            Button("삭제", action: onDelete)
                .dsTextStyle(DSTypography.bodyRegular24)
                .foregroundStyle(DSPalette.Gray.g300)
                .frame(minWidth: 42, minHeight: 42)
                .accessibilityLabel("\(record.trainingName) 기록 삭제")
                .accessibilityIdentifier("trainingHistory.delete.\(record.sessionID.uuidString)")
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            if let image = store.trainingHistoryThumbnail(for: record) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(DSColor.backgroundElevated)
                    .overlay {
                        Image(systemName: "map")
                            .font(.system(size: 36, weight: .regular))
                            .foregroundStyle(DSColor.contentTertiary)
                    }
            }

            if isOpening {
                Rectangle()
                    .fill(.black.opacity(0.4))
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("AAR 불러오는 중")
            }
        }
    }
}

extension TrainingHistoryRecord {
    private static let startedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd_HH:mm"
        return formatter
    }()

    /// `2026.10.20_13:30`
    var startedAtText: String { Self.startedAtFormatter.string(from: startedAt) }

    /// 목록 설명 줄. 도면 이름이 없으면 빼고 보여준다.
    var detailText: String {
        [floorPlanName, participantSummary, startedAtText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// `13:24`. 한 시간을 넘으면 `1:02:03`
    var durationText: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview("이전 훈련 기록") {
    let floorPlan = FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "preview")
    let records = (0..<3).map { index in
        TrainingHistoryRecord(
            sessionID: UUID(),
            trainingName: "A-3거점 진입 절차 동계 훈련",
            floorPlan: floorPlan,
            floorPlanName: "훈련장 B",
            participantNames: ["강유키"] + (1..<16).map { "대원 \($0)" },
            startedAt: Date(timeIntervalSince1970: 1_760_934_600 - Double(index) * 7_200),
            endedAt: Date(timeIntervalSince1970: 1_760_934_600 - Double(index) * 7_200 + 804)
        )
    }
    return TrainingHistoryView()
        .environment(InstructorStore(trainingHistory: records))
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#Preview("기록 없음") {
    TrainingHistoryView()
        .environment(InstructorStore())
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
