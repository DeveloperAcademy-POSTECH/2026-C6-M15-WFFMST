#if DEBUG
import SwiftUI

private enum PreviewSegment: String, CaseIterable {
    case pen = "펜툴"
    case brush = "브러쉬"
}

private struct DesignSystemPreview: View {
    @State private var text = ""
    @State private var segment: PreviewSegment = .pen
    @State private var sliderValue = 0.5
    @State private var selectedPill = 0
    @FocusState private var focusedField: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.s40) {
                buttonSection
                inputSection
                displaySection
            }
            .padding(DSSpacing.s40)
        }
        .background(DSColor.backgroundPrimary)
        .preferredColorScheme(.dark)
    }

    private var buttonSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s16) {
            sectionTitle("Button · default / disabled / selected")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: DSSpacing.s16) {
                Button("도면 생성") {}
                    .buttonStyle(.dsPrimary)

                Button("이전") {}
                    .buttonStyle(.dsSecondary)

                Button("비활성") {}
                    .buttonStyle(.dsPrimary)
                    .disabled(true)

                HStack {
                    Button {} label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.dsCircular)

                    Button("선택 전") { selectedPill = 0 }
                        .buttonStyle(DSSelectablePillStyle(isSelected: selectedPill == 0))

                    Button("선택됨") { selectedPill = 1 }
                        .buttonStyle(DSSelectablePillStyle(isSelected: selectedPill == 1))
                }
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s24) {
            sectionTitle("Input · placeholder / filled / focused / disabled")

            TextField(
                "훈련명을 입력하세요",
                text: $text,
                prompt: Text("훈련명을 입력하세요").foregroundColor(DSColor.contentTertiary)
            )
            .focused($focusedField)
            .textFieldStyle(.ds(isFocused: focusedField))

            TextField("비활성 입력", text: .constant("수정할 수 없는 값"))
                .textFieldStyle(.dsDefault)
                .disabled(true)

            DSSegmentedControl(
                options: PreviewSegment.allCases,
                selection: $segment,
                title: \.rawValue
            )

            DSLabeledSlider("벽 레이어 투명도", value: $sliderValue)
        }
        .frame(maxWidth: 520)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s20) {
            sectionTitle("Display · long Korean / status")
            DSFloatingBanner("추가/지우기 버튼을 먼저 누른 후 필요한 영역을 그리듯 조작하세요. 긴 안내 문구도 잘리지 않고 여러 줄로 표시됩니다.")
            HStack {
                DSStepIndicator(current: 1, total: 5)
                DSStatusBadge("준비 완료", tone: .success)
                DSStatusBadge("오류", tone: .error)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .dsTextStyle(DSTypography.captionMedium14)
            .foregroundStyle(DSColor.contentSecondary)
    }
}

#Preview("CQB Design System · iPad") {
    DesignSystemPreview()
        .frame(width: 1_366, height: 1_024)
}

#Preview("CQB Design System · iPhone · Accessibility") {
    DesignSystemPreview()
        .dynamicTypeSize(.accessibility3)
        .frame(width: 393, height: 852)
}
#endif
