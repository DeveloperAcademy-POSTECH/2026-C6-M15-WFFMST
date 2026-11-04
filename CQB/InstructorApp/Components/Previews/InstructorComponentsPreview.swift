#if DEBUG
import CQBDesignSystem
import SwiftUI

private enum PreviewEditorMode: String, CaseIterable {
    case block = "막기"
    case erase = "열기"
}

/// InstructorApp의 실제 iPad 화면에서 사용하는 앱 전용 컴포넌트 카탈로그입니다.
private struct InstructorComponentsPreview: View {
    @State private var editorMode = PreviewEditorMode.block
    @State private var selectedPill = 0
    @State private var opacity = 0.65

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: DSSpacing.s24
            ) {
                previewSection("Navigation") {
                    HStack(spacing: DSSpacing.s24) {
                        previewItem("공통 뒤로가기 · 55×55") {
                            InstructorBackButton(action: {})
                        }
                    }
                }

                previewSection("Step indicator") {
                    HStack(spacing: DSSpacing.s24) {
                        InstructorStepIndicator(current: 1, total: 4)
                        InstructorStepIndicator(current: 4, total: 4)
                    }
                }

                previewSection("Action button · 고정 180×55") {
                    HStack(spacing: DSSpacing.s12) {
                        ActionButton("Primary", width: .fixed180, action: {})
                        ActionButton(
                            "Secondary",
                            tone: .secondary,
                            width: .fixed180,
                            action: {}
                        )
                        ActionButton("Disabled", width: .fixed180, action: {})
                            .disabled(true)
                    }
                }

                previewSection("Action button · 기본 크기") {
                    VStack(alignment: .leading, spacing: DSSpacing.s12) {
                        ActionButton("Primary", action: {})
                        ActionButton(
                            "Secondary + icon",
                            systemImage: "plus",
                            tone: .secondary,
                            action: {}
                        )
                    }
                }

                previewSection("Action button · 가로 채움") {
                    VStack(spacing: DSSpacing.s12) {
                        ActionButton("Primary", width: .fill, action: {})
                        ActionButton("Secondary", tone: .secondary, width: .fill, action: {})
                        ActionButton("Disabled", width: .fill, action: {})
                            .disabled(true)
                    }
                }

                previewSection("홈 전용 CTA · 311×56") {
                    HStack(spacing: DSSpacing.s24) {
                        HomeTrainingStartButton(isEnabled: true, action: {})
                        HomeTrainingStartButton(isEnabled: false, action: {})
                    }
                }

                previewSection("Segmented control") {
                    InstructorSegmentedControl(
                        options: PreviewEditorMode.allCases,
                        selection: $editorMode,
                        title: \.rawValue
                    )
                }

                previewSection("Selectable pill") {
                    HStack(spacing: DSSpacing.s12) {
                        pill("선택 전", value: 0)
                        pill("선택됨", value: 1)
                        pill("비활성", value: 2)
                            .disabled(true)
                    }
                }

                previewSection("Labeled slider") {
                    InstructorLabeledSlider("도면 투명도", value: $opacity)
                }
            }
            .padding(DSSpacing.s32)
        }
        .background(DSColor.backgroundPrimary)
        .preferredColorScheme(.dark)
    }

    private func pill(_ title: String, value: Int) -> some View {
        Button(title) {
            selectedPill = value
        }
        .buttonStyle(InstructorSelectablePillStyle(isSelected: selectedPill == value))
    }

    private func previewSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s16) {
            Text(title)
                .dsTextStyle(DSTypography.headingSemiBold20)
                .foregroundStyle(DSColor.contentPrimary)

            content()
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .padding(DSSpacing.s24)
        .background(DSColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
    }

    private func previewItem<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s8) {
            Text(title)
                .dsTextStyle(DSTypography.captionRegular14)
                .foregroundStyle(DSColor.contentSecondary)
            content()
        }
    }
}

#Preview("Instructor components · iPad", traits: .fixedLayout(width: 1366, height: 1024)) {
    InstructorComponentsPreview()
}
#endif
