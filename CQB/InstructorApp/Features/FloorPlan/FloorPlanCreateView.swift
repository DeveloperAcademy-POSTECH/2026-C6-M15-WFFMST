import CQBDesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct FloorPlanCreateView: View {
    @Environment(InstructorStore.self) private var app
    @Environment(FloorPlanDraftStore.self) private var store
    @State private var importer = FloorPlanImportPresentation()
    @State private var layers = FloorPlanLayerDisplay(planOpacity: 0.5, maskOpacity: 0.5)
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable { case name, distance }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                previewArea
            }
            .containerRelativeFrame(.horizontal, count: 10, span: 7, spacing: 0)
            .frame(maxHeight: .infinity)
            .background(InstructorColor.canvas)

            sidePanel
                .containerRelativeFrame(.horizontal, count: 10, span: 3, spacing: 0)
        }
        .background(InstructorColor.canvas.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .background(FloorPlanInputAnchor(presentation: importer).frame(width: 0, height: 0))
        .fileImporter(
            isPresented: Binding(
                get: { importer.isPresented },
                set: { importer.isPresented = $0 }
            ),
            allowedContentTypes: [.png, .jpeg]
        ) { result in
            switch result {
            case .success(let url): store.importImage(from: url)
            case .failure(let error): store.reportImportFailure(error)
            }
        }
        .onChange(of: importer.isPresented) { _, presented in
            if !presented { importer.finish() }
        }
        .onDisappear { importer.finish() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            InstructorBackButton(action: app.goBack)

            Text(store.image?.fileName ?? "도면 설정")
                .font(DSTypography.h2)
                .foregroundStyle(InstructorColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            ActionButton(
                store.image == nil ? "파일 첨부" : "파일 변경",
                tone: .secondary,
                density: .file
            ) {
                importer.request { focusedField = nil }
            }
            .disabled(store.isProcessing || store.isDrawing)
            .accessibilityIdentifier("floorPlan.import")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private var previewArea: some View {
        GeometryReader { geometry in
            let topInset = previewTopInset(for: geometry.size.height)
            let cardSize = previewCardSize(in: geometry.size, topInset: topInset)

            ZStack {
                VStack(spacing: 0) {
                    previewCard
                        .frame(width: cardSize.width, height: cardSize.height)

                    Spacer(minLength: 24)

                    HStack {
                        if store.step == .editing, store.image != nil {
                            historyControls
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 52)
                }
                .padding(.horizontal, 24)
                .padding(.top, topInset)
                .padding(.bottom, 24)

                statusOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("도면 미리보기")
                .font(DSTypography.h3)
                .foregroundStyle(InstructorColor.textPrimary)
                .frame(height: 24)

            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 4))

            if store.image != nil, store.step == .editing {
                Text("출발점·방향은 대원 기기에서 보정")
                    .font(DSTypography.bodySmall)
                    .foregroundStyle(InstructorColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
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

    private func previewTopInset(for availableHeight: CGFloat) -> CGFloat {
        min(56, max(24, availableHeight * 0.06))
    }

    private func previewCardSize(in availableSize: CGSize, topInset: CGFloat) -> CGSize {
        let referenceSize = CGSize(width: 702, height: 728)
        let availableWidth = max(0, availableSize.width - 48)
        let availableHeight = max(0, availableSize.height - topInset - 24 - 52 - 24)
        return CGSize(
            width: min(referenceSize.width, availableWidth),
            height: min(referenceSize.height, availableHeight)
        )
    }

    @ViewBuilder
    private var canvas: some View {
        if let image = store.previewImage {
            LocalFloorPlanCanvas(
                image: image,
                mask: store.maskImage,
                tool: store.tool,
                normalizedDiameter: store.normalizedDiameter,
                outline: store.outline,
                selection: store.selection,
                pendingBrushStrokes: store.pendingBrushStrokes,
                scaleA: store.scaleA,
                scaleB: store.scaleB,
                scaleLabel: nil,
                importPresentation: importer,
                layers: layers,
                onStroke: store.stageBrushStroke,
                onPoint: store.placePoint,
                onScaleMarkerMoved: store.moveScaleMarker,
                onEditingChanged: store.setDrawing
            )
            .allowsHitTesting(!store.isProcessing)
            .accessibilityIdentifier("floorPlan.canvas")
        } else {
            Text("이미지가 업로드 되지 않았습니다.")
                .font(DSTypography.bodySmall)
                .foregroundStyle(InstructorColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var historyControls: some View {
        HStack(spacing: 8) {
            historyButton(asset: "InstructorUndoIcon", label: "실행 취소", enabled: store.canUndo, action: store.undo)
            historyButton(asset: "InstructorRedoIcon", label: "다시 실행", enabled: store.canRedo, action: store.redo)
        }
        .padding(4)
        .frame(width: 104, height: 52)
        .background(InstructorColor.surfaceBase)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
    }

    private func historyButton(asset: String, label: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(asset)
                .renderingMode(.original)
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var sidePanel: some View {
        Group {
            if store.step == .scaling {
                scalePanel
            } else {
                editingPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstructorColor.surfaceBase)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(InstructorColor.borderDefault)
                .frame(width: 1)
        }
    }

    private var editingPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("벽 편집")
                        .font(DSTypography.h2)
                        .foregroundStyle(InstructorColor.textPrimary)

                    Text("인식되지 않은 부분을 추가하거나 지우세요")
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(InstructorColor.textSecondary)
                        .padding(.top, 8)

                    editorControls
                        .padding(.top, 20)

                    FloorPlanLayerControls(display: $layers)
                        .padding(.top, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }

            ActionButton("다음", fillsWidth: true, action: store.continueToScale)
                .frame(height: 52)
                .disabled(!store.canContinueEditing)
                .accessibilityIdentifier("floorPlan.next.scale")
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
        }
    }

    private var editorControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorTabs

            Group {
                if store.editorMode == .pen {
                    penControls
                } else {
                    brushControls
                }
            }
            .padding(.top, 24)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(InstructorColor.surfaceRaised)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
        .disabled(store.image == nil || store.isProcessing || importer.isPresented)
    }

    private var editorTabs: some View {
        HStack(spacing: 4) {
            editorTab("펜툴", mode: .pen)
            editorTab("브러시", mode: .brush)
        }
        .padding(4)
        .frame(height: 44)
        .background(InstructorColor.canvas)
        .clipShape(.rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
        }
    }

    private func editorTab(_ title: String, mode: LocalFloorPlanEditorMode) -> some View {
        let selected = store.editorMode == mode
        return Button(title) { store.setEditorMode(mode) }
            .font(Self.mediumBodyFont)
            .foregroundStyle(selected ? InstructorColor.canvas : InstructorColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            .background(selected ? InstructorColor.actionPrimary : .clear)
            .clipShape(.rect(cornerRadius: 4))
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var penControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("필요한 영역을 점으로 찍어 선택하세요")
                .font(DSTypography.bodySmall)
                .foregroundStyle(InstructorColor.textPrimary)

            panelButton("외곽 추가하기", enabled: store.canApplySelection, action: store.applyOutlineSelection)
                .padding(.top, 24)

            Text("선택영역의 외부를 통과 불가 영역으로 지정합니다")
                .font(DSTypography.caption)
                .foregroundStyle(InstructorColor.textSecondary)
                .padding(.top, 12)

            panelButton("선택영역 추가하기", enabled: store.canApplySelection) {
                store.applySelection(.block)
            }
            .padding(.top, 24)

            panelButton("선택영역 삭제하기", enabled: store.canApplySelection) {
                store.applySelection(.open)
            }
            .padding(.top, 12)

            Text("선택영역의 내부에 장애물을 추가하거나 삭제합니다")
                .font(DSTypography.caption)
                .foregroundStyle(InstructorColor.textSecondary)
                .padding(.top, 12)
        }
    }

    private var brushControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("필요한 영역을 그리세요")
                .font(DSTypography.bodySmall)
                .foregroundStyle(InstructorColor.textPrimary)

            HStack(spacing: 12) {
                panelButton("추가하기", enabled: store.canApplyBrush) {
                    store.applyPendingBrush(.block)
                }
                panelButton("지우기", enabled: store.canApplyBrush) {
                    store.applyPendingBrush(.open)
                }
            }
            .padding(.top, 24)

            FloorPlanLabeledSlider(
                label: "브러시 크기",
                value: Binding(
                    get: { store.normalizedDiameter },
                    set: store.setBrushDiameter
                ),
                range: 0.001...0.05,
                step: 0.001,
                formattedValue: { value in
                    guard let image = store.image else { return "–" }
                    let points = value * Double(min(image.width, image.height))
                    return "\(Int(points.rounded()))pt"
                }
            )
            .padding(.top, 32)
        }
    }

    private func panelButton(_ title: String, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        ActionButton(title, tone: .secondary, fillsWidth: true, action: action)
            .frame(height: 48)
            .disabled(!enabled)
    }

    private var scalePanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("축척 설정")
                        .font(DSTypography.h2)
                        .foregroundStyle(InstructorColor.textPrimary)

                    Text("A지점과 B지점이 될 부분을 클릭하세요.")
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(InstructorColor.textSecondary)
                        .padding(.top, 8)

                    HStack(spacing: 12) {
                        Text("A-B 실제 거리")
                            .font(Self.mediumBodyFont)
                            .foregroundStyle(InstructorColor.textPrimary)
                        Spacer()
                        TextField(
                            "입력",
                            text: Binding(get: { store.distanceText }, set: store.setDistance)
                        )
                        .focused($focusedField, equals: .distance)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(DSTypography.body)
                        .foregroundStyle(InstructorColor.textPrimary)
                        .tint(InstructorColor.actionPrimary)
                        .frame(maxWidth: 104, minHeight: 48)
                        .background(InstructorColor.canvas)
                        .clipShape(.rect(cornerRadius: 4))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
                        }
                        .accessibilityIdentifier("floorPlan.distance")
                        Text("m")
                            .font(DSTypography.body)
                            .foregroundStyle(InstructorColor.textPrimary)
                    }
                    .padding(.top, 50)

                    Text("도면 이름 설정")
                        .font(DSTypography.h2)
                        .foregroundStyle(InstructorColor.textPrimary)
                        .padding(.top, 32)

                    TextField(
                        "훈련장 A",
                        text: Binding(get: { store.name }, set: store.setName),
                        prompt: Text("훈련장 A").foregroundStyle(InstructorColor.textSecondary)
                    )
                    .focused($focusedField, equals: .name)
                    .font(DSTypography.body)
                    .foregroundStyle(InstructorColor.textPrimary)
                    .tint(InstructorColor.actionPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .background(InstructorColor.canvas)
                    .clipShape(.rect(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
                    }
                    .padding(.top, 8)
                    .accessibilityIdentifier("floorPlan.name")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }

            ActionButton("저장", fillsWidth: true, action: app.registerFloorPlan)
                .frame(height: 52)
                .disabled(!store.canRegister)
                .accessibilityIdentifier("floorPlan.save")
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if (store.isProcessing && !store.isReplayingEdits)
            || store.errorMessage != nil || importer.message != nil {
            VStack(alignment: .leading, spacing: 8) {
                if store.isProcessing && !store.isReplayingEdits {
                    HStack {
                        ProgressView()
                        Text(store.activity)
                        Button("취소", action: store.cancelProcessing)
                    }
                }
                if let error = store.errorMessage {
                    Text(error)
                        .foregroundStyle(InstructorColor.validationError)
                        .accessibilityIdentifier("floorPlan.error")
                }
                if let message = importer.message {
                    Text(message).foregroundStyle(InstructorColor.validationError)
                }
            }
            .font(DSTypography.bodySmall)
            .foregroundStyle(InstructorColor.textPrimary)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private static let mediumBodyFont: Font = {
        DSFonts.register()
        return .custom("NotoSansKR-Medium", size: 16, relativeTo: .body)
    }()
}

#Preview("도면 생성 · 파일 미첨부") {
    let app = InstructorStore()
    return FloorPlanCreateView()
        .environment(app)
        .environment(app.floorPlanDraft)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
