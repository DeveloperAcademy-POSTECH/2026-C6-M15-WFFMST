#if DEBUG
import SwiftUI

private struct DesignSystemPreview: View {
    @State private var focusedText = "포커스 상태를 확인하세요"
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
                    Button {
                        focusedField = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.dsCircular(size: .regular))

                    Button {
                        focusedField = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.dsCircular(size: .compact))

                }
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s24) {
            sectionTitle("Input · placeholder / filled / focused / disabled")

            TextField("Placeholder", text: .constant(""), prompt: placeholder("훈련명을 입력하세요"))
                .textFieldStyle(.dsDefault)

            TextField("Filled", text: .constant("야간 실내 전술 훈련"))
                .textFieldStyle(.dsDefault)

            TextField("Focused", text: $focusedText)
                .focused($focusedField)
                .textFieldStyle(.ds(isFocused: focusedField))

            TextField("비활성 입력", text: .constant("수정할 수 없는 값"))
                .textFieldStyle(.dsDefault)
                .disabled(true)

        }
        .frame(maxWidth: 520)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s20) {
            sectionTitle("Guide Toast · regular / compact / card")
            DSGuideToast(
                "추가/지우기 버튼을 먼저 누른 후 필요한 영역을 그리듯 조작하세요. 긴 안내 문구도 잘리지 않고 여러 줄로 표시됩니다.",
                type: .regular
            )
            DSGuideToast(
                "출발 위치를 선택한 후\n바라보는 방향을 설정해 주세요",
                type: .compact
            )
            DSGuideToast(
                "주변 공간을 천천히 스캔해 주세요.\n인식이 완료되면 다음 단계로 이동합니다.",
                type: .card
            )
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .dsTextStyle(DSTypography.captionMedium14)
            .foregroundStyle(DSColor.contentSecondary)
    }

    private func placeholder(_ text: String) -> Text {
        Text(text).foregroundColor(DSColor.contentTertiary)
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
