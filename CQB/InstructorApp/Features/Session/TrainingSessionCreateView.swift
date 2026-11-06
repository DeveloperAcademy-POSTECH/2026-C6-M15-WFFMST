import CQBDesignSystem
import SwiftUI

struct TrainingSessionCreateView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("새 훈련 세션")
                .dsTextStyle(DSTypography.headingBold36)
                .foregroundStyle(DSColor.contentPrimary)
                .frame(height: 43, alignment: .leading)

            trainingNameField
                .padding(.top, 12)

            GeometryReader { proxy in
                let previewWidth = max(0, proxy.size.width - 517 - 40)

                HStack(alignment: .top, spacing: 40) {
                    floorPlanList
                        .frame(width: 517, height: proxy.size.height)
                        .zIndex(1)

                    floorPlanPreview
                        .frame(width: previewWidth, height: proxy.size.height)
                        .clipped()
                        .zIndex(0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .padding(.top, 60)
        }
        .padding(.top, 195)
        .padding(.horizontal, 40)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.backgroundPrimary)
        .overlay(alignment: .top) {
            header
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            InstructorBackButton(action: store.goBack)
            .disabled(store.isCreatingSession)

            Spacer()

            Button(action: store.createSession) {
                Text("세션 생성")
                    .padding(.vertical, DSSpacing.s12)
                    // DSPrimaryButtonStyle의 좌우 20pt padding을 포함해 최종 너비 180pt.
                    .frame(width: 140)
            }
            .buttonStyle(.dsPrimary)
            .disabled(!store.canCreateSession)
            .accessibilityIdentifier("session.create")
        }
        .padding(.top, 40)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var trainingNameField: some View {
        ZStack(alignment: .leading) {
            TextField(
                "",
                text: Binding(
                    get: { store.trainingName },
                    set: store.setTrainingName
                )
            )
            .textFieldStyle(.dsDefault)

            if store.trainingName.isEmpty {
                Text("훈련명을 입력하세요")
                    .dsTextStyle(DSTypography.headingSemiBold20)
                    .foregroundStyle(DSPalette.Gray.g300)
                    .padding(.horizontal, DSSpacing.s20)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .disabled(store.isCreatingSession)
        .frame(width: 517, height: 58)
        .accessibilityLabel("훈련명")
        .accessibilityIdentifier("session.name")
        .overlay(alignment: .bottomLeading) {
            if let error = store.sessionCreationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .dsTextStyle(DSTypography.captionRegular14)
                    .foregroundStyle(DSColor.statusError)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: 32)
                    .accessibilityIdentifier("session.creationError")
            }
        }
    }

    private var floorPlanList: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s40) {
            Text("훈련 도면")
                .dsTextStyle(DSTypography.headingBold20)
                .foregroundStyle(DSColor.contentPrimary)

            if store.floorPlans.isEmpty {
                emptyFloorPlanList
            } else {
                ScrollView {
                    LazyVStack(spacing: DSSpacing.s4) {
                        ForEach(store.floorPlans) { floorPlan in
                            floorPlanRow(floorPlan)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("session.plan")
            }
        }
        .padding(DSSpacing.s12)
        .background(DSColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.large)
                .stroke(DSColor.borderPrimary, lineWidth: 1)
        }
        .disabled(store.isCreatingSession)
    }

    private func floorPlanRow(_ floorPlan: InstructorFloorPlan) -> some View {
        let isSelected = store.selectedFloorPlanID == floorPlan.id

        return Button {
            store.selectFloorPlan(floorPlan.id)
        } label: {
            HStack(spacing: DSSpacing.s32) {
                selectionIndicator(isSelected: isSelected)

                VStack(alignment: .leading, spacing: DSSpacing.s8) {
                    Text(floorPlan.name)
                        .dsTextStyle(DSTypography.headingSemiBold24)
                        .foregroundStyle(isSelected ? DSColor.contentPrimary : DSColor.contentSecondary)
                        .lineLimit(1)

                    Text("생성일 \(formattedCreationDate(floorPlan.createdAt))")
                        .dsTextStyle(DSTypography.bodyRegular16)
                        .foregroundStyle(isSelected ? DSColor.contentPrimary : DSColor.contentSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 22)
            .padding(.trailing, DSSpacing.s20)
            .padding(.vertical, DSSpacing.s16)
            .frame(maxWidth: .infinity, minHeight: 95, alignment: .leading)
            .background(isSelected ? DSColor.surfaceSelected : DSColor.surfacePrimary)
            .clipShape(.rect(cornerRadius: DSRadius.large))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(floorPlan.name), 생성일 \(formattedCreationDate(floorPlan.createdAt))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("session.plan.\(floorPlan.id)")
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(
                    isSelected ? DSPalette.Primary.p300 : InstructorColor.floorPlanSelectionIdle,
                    lineWidth: isSelected ? 2 : 1.5
                )
            if isSelected {
                Circle()
                    .fill(DSPalette.Primary.p300)
                    .padding(DSSpacing.s4)
            }
        }
        .frame(width: DSSpacing.s24, height: DSSpacing.s24)
        .accessibilityHidden(true)
    }

    private var emptyFloorPlanList: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("등록된 도면이 없습니다.")
                .dsTextStyle(DSTypography.headingSemiBold24)
                .foregroundStyle(DSColor.contentSecondary)

            Button("도면 등록 바로가기", action: store.openFloorPlanList)
                .dsTextStyle(DSTypography.headingSemiBold20)
                .foregroundStyle(DSColor.actionPrimary)
                .padding(10)
                .buttonStyle(.plain)
                .accessibilityIdentifier("session.floorPlanShortcut")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("session.plan.empty")
    }

    private var floorPlanPreview: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                DSColor.surfaceSecondary

                if let image = store.selectedPlanImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                        .accessibilityLabel("선택한 훈련 도면")

                    InstructorColor.floorPlanPreviewOverlay
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                } else {
                    previewStatus
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                Text("도면 미리보기")
                    .dsTextStyle(DSTypography.headingBold20)
                    .foregroundStyle(DSColor.surfaceSelected)
                    .padding(20)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: DSRadius.large))
        }
        .accessibilityIdentifier("session.planPreview")
    }

    @ViewBuilder
    private var previewStatus: some View {
        switch store.sessionFloorPlanPreviewState {
        case .loading:
            ProgressView()
                .tint(DSPalette.Primary.p300)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("도면 미리보기 불러오는 중")
        case .failed(let message):
            VStack(spacing: 16) {
                Text(message)
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(DSColor.contentSecondary)
                    .multilineTextAlignment(.center)

                Button("다시 불러오기", action: store.retrySessionFloorPlanPreview)
                    .buttonStyle(.dsSecondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("session.planPreview.error")
        case .idle, .loaded:
            EmptyView()
        }
    }

    private func formattedCreationDate(_ date: Date) -> String {
        Self.creationDateFormatter.string(from: date)
    }

    private static let creationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()
}

#Preview("새 훈련 세션 · 도면 있음") {
    let store = InstructorStore(floorPlans: [
        InstructorFloorPlan(
            id: "preview-plan-1",
            name: "훈련장 A 도면 v1",
            fileName: "훈련장 A 도면.png",
            referenceDistance: 15,
            createdAt: Date(timeIntervalSince1970: 1_792_454_400)
        ),
        InstructorFloorPlan(
            id: "preview-plan-2",
            name: "훈련장 B 도면 v1",
            fileName: "훈련장 B 도면.png",
            referenceDistance: 12,
            createdAt: Date(timeIntervalSince1970: 1_792_454_400)
        )
    ])
    store.openSessionCreation()

    return TrainingSessionCreateView()
        .environment(store)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#Preview("새 훈련 세션 · 도면 없음") {
    let store = InstructorStore(floorPlans: [])
    store.loadFloorPlans()
    store.openSessionCreation()

    return TrainingSessionCreateView()
        .environment(store)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
