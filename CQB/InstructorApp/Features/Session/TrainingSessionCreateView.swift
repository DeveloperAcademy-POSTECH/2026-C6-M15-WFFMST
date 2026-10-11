import CQBDesignSystem
import SwiftUI

struct TrainingSessionCreateView: View {
    @Environment(InstructorStore.self) private var store

    var body: some View {
        DropdownHost {
            VStack(alignment: .leading, spacing: 0) {
                InstructorBackButton(action: store.goBack)

                Text("새 훈련 세션")
                    .font(DSTypography.h1)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .frame(height: 48, alignment: .leading)

                HStack(alignment: .top, spacing: 24) {
                    sessionFields
                        .frame(minWidth: 320, idealWidth: 544, maxWidth: 544, alignment: .topLeading)

                    planPreview
                        .frame(minWidth: 420, maxWidth: 702, maxHeight: 728)
                }
                .padding(.top, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack {
                    Spacer()
                    ActionButton("세션 생성", action: store.createSession)
                        .frame(width: 354, height: 52)
                        .disabled(!store.canCreateSession)
                        .accessibilityIdentifier("session.create")
                }
                .padding(.top, 32)
            }
            .padding(.top, 32)
            .padding(.horizontal, 48)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.canvas.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var sessionFields: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                Text("훈련명")
                    .font(DSTypography.h3)
                    .foregroundStyle(InstructorColor.textPrimary)

                InstructorTextField(
                    title: "훈련명",
                    placeholder: "훈련명을 입력하세요",
                    text: Binding(
                        get: { store.trainingName },
                        set: store.setTrainingName
                    )
                )
                .accessibilityIdentifier("session.name")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("훈련 도면")
                    .font(DSTypography.h3)
                    .foregroundStyle(InstructorColor.textPrimary)

                SingleSelectionMenu(
                    title: "훈련 도면",
                    options: store.floorPlans,
                    selection: store.selectedFloorPlanID,
                    optionTitle: \.name,
                    fieldBackground: InstructorColor.surfaceRaised,
                    menuFillsFieldWidth: true,
                    onSelect: store.selectFloorPlan
                )
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("session.plan")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planPreview: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("도면 미리보기")
                .font(DSTypography.h3)
                .foregroundStyle(InstructorColor.textPrimary)
                .frame(height: 24, alignment: .leading)

            Group {
                if let image = store.selectedPlanImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.5)
                        .accessibilityLabel("선택한 훈련 도면")
                } else {
                    ContentUnavailableView(
                        "도면 미리보기 없음",
                        systemImage: "map",
                        description: Text("저장된 훈련 도면을 선택하세요.")
                    )
                    .foregroundStyle(InstructorColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 4))

            Text("출발점·방향은 대원 기기에서 보정")
                .font(DSTypography.bodySmall)
                .foregroundStyle(InstructorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
    }
}

#Preview("새 훈련 세션") {
    let store = InstructorStore(floorPlans: [
        DemoFloorPlan(
            id: "preview-plan",
            name: "훈련장 A 도면",
            fileName: "훈련장 A 도면.png",
            referenceDistance: 15
        )
    ])
    store.openSessionCreation()

    return TrainingSessionCreateView()
        .environment(store)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
