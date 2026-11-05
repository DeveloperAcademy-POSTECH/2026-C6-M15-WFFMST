import CQBDesignSystem
import CQBCore
import SwiftUI
import UniformTypeIdentifiers

struct FloorPlanCreateView: View {
    private let referenceScreenWidth: CGFloat = 1_366
    private let referenceSidebarWidth: CGFloat = 404
    private let minimumSidebarWidth: CGFloat = 360
    private let maximumPreviewWidth: CGFloat = 409
    private let maximumPreviewHeight: CGFloat = 864

    @Environment(InstructorStore.self) private var app
    @Environment(FloorPlanDraftStore.self) private var store
    @State private var importer = FloorPlanImportPresentation()
    @State private var layers = FloorPlanLayerDisplay(
        planOpacity: 1,
        maskOpacity: 1,
        tint: .red
    )
    @State private var showsNameValidation = false
    @State private var showsExitConfirmation = false
    @State private var registrationBrushMode: LocalEditMode = .block
    @State private var editingCanvasDisplayScale: CGFloat = 1
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable { case name, distance }

    private var isImportInteractionActive: Bool {
        importer.isPreparing || importer.isPresented || store.isImporting
    }

    private var scanCheckpointMarkers: [LocalScanCheckpointMarker] {
        store.scanCheckpoints.enumerated().map { index, point in
            let state: LocalScanCheckpointState
            if store.step == .scanning && store.completedScanCheckpointIndices.contains(index) {
                state = .completed
            } else if store.step == .scanning && store.selectedScanCheckpointIndex == index {
                state = .selected
            } else {
                state = .planned
            }
            return LocalScanCheckpointMarker(point: point, number: index + 1, state: state)
        }
    }

    private var preparationCheckpointMarkers: [LocalScanCheckpointMarker] {
        store.scanCheckpoints.enumerated().map { index, point in
            LocalScanCheckpointMarker(point: point, number: index + 1, state: .planned)
        }
    }

    private var scanningLocationMarkers: [LocalScanCheckpointMarker] {
        scanCheckpointMarkers
    }

    private var scanCheckpointTapHandler: ((Int) -> Void)? {
        guard store.worldMapStart != nil else { return nil }
        return handleScanMarkerTap
    }

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(
                referenceSidebarWidth,
                max(
                    minimumSidebarWidth,
                    proxy.size.width * referenceSidebarWidth / referenceScreenWidth
                )
            )

            switch store.step {
            case .information:
                informationStep(sidebarWidth: sidebarWidth)
            case .alignment:
                alignmentStep(sidebarWidth: sidebarWidth)
            case .scanning:
                scanningStep(sidebarWidth: sidebarWidth)
            case .editing:
                editingStep(sidebarWidth: sidebarWidth)
            }
        }
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .background(
            FloorPlanInputAnchor(presentation: importer) { focusedField = nil }
                .frame(width: 0, height: 0)
        )
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
        .alert("도면 등록을 종료할까요?", isPresented: $showsExitConfirmation) {
            Button("나가기", role: .destructive, action: app.goBack)
            Button("계속 등록", role: .cancel) {}
        } message: {
            Text("지금 나가면 입력한 도면 설정 정보가 저장되지 않습니다.")
        }
        .alert("공간 스캔을 저장하지 못했습니다", isPresented: Binding(
            get: { store.worldMapSaveErrorMessage != nil },
            set: { if !$0 { store.dismissWorldMapSaveError() } }
        )) {
            Button("확인", role: .cancel, action: store.dismissWorldMapSaveError)
        } message: {
            Text(store.worldMapSaveErrorMessage ?? "")
        }
        .overlay {
            if app.isUploadingFloorPlan {
                floorPlanSavingOverlay
            }
        }
        .task {
            await Task.yield()
            guard store.step == .information, store.image == nil,
                  !app.isEditingFloorPlan else { return }
            importer.request { focusedField = nil }
        }
        .onDisappear { importer.finish() }
    }

    private func informationStep(sidebarWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            informationPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            informationPanel
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .disabled(isImportInteractionActive || app.isUploadingFloorPlan
                    || app.floorPlanUploadError != nil)
        }
    }

    private func alignmentStep(sidebarWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            alignmentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            alignmentPanel
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .disabled(isImportInteractionActive || app.isUploadingFloorPlan
                    || app.floorPlanUploadError != nil)
        }
    }

    private func scanningStep(sidebarWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            scanningPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            scanningPanel
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .disabled(isImportInteractionActive || app.isUploadingFloorPlan
                    || app.floorPlanUploadError != nil)
        }
    }

    private func editingStep(sidebarWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            editingPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            editingRegistrationPanel
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .disabled(isImportInteractionActive || app.isUploadingFloorPlan
                    || app.floorPlanUploadError != nil)
        }
    }

    private var editingPreview: some View {
        ZStack(alignment: .topLeading) {
            DSColor.backgroundPrimary

            if let image = store.previewImage {
                LocalFloorPlanCanvas(
                    image: image,
                    mask: store.maskImage,
                    tool: store.tool,
                    normalizedDiameter: store.normalizedDiameter,
                    selection: store.selection,
                    usesTransparentBackground: true,
                    maximumInitialDisplaySize: CGSize(
                        width: maximumPreviewWidth,
                        height: maximumPreviewHeight
                    ),
                    imageToneOverlayOpacity: 0,
                    importPresentation: importer,
                    layers: layers,
                    onStroke: { stroke in
                        store.applyBrushStroke(stroke, as: registrationBrushMode)
                    },
                    onPoint: store.placePoint,
                    onEditingChanged: store.setDrawing,
                    onDisplayScaleChanged: { editingCanvasDisplayScale = $0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(!store.isImporting && store.processingStage != .preparingPreview
                    && !app.isUploadingFloorPlan
                    && app.floorPlanUploadError == nil)
                .accessibilityIdentifier("floorPlan.editing.canvas")
            }

            InstructorBackButton(action: handleTopBack)
                .disabled(!app.canGoBack)
                .padding(.top, DSSpacing.s40)
                .padding(.leading, DSSpacing.s40)

            DSGuideToast(editingGuideMessage)
                .frame(maxWidth: store.editorMode == .pen ? 734 : 690, minHeight: 100)
                .padding(.leading, 175)
                .padding(.trailing, DSSpacing.s40)
                .padding(.top, DSSpacing.s40)

            editingHistoryControls
                .padding(.leading, 40)
                .padding(.bottom, 41)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            statusOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 156)
                .padding(.trailing, 40)
        }
    }

    private var editingHistoryControls: some View {
        HStack(spacing: 0) {
            editingHistoryButton(
                systemImage: "return",
                label: "실행 취소",
                enabled: store.canUndo,
                action: store.undo
            )
            editingHistoryButton(
                systemImage: "return.right",
                label: "다시 실행",
                enabled: store.canRedo,
                action: store.redo
            )
        }
        .padding(.horizontal, 7)
        .frame(width: 194, height: 50)
        .background(DSColor.borderPrimary)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(DSColor.surfaceSecondary, lineWidth: 1)
        }
    }

    private func editingHistoryButton(
        systemImage: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DSColor.contentPrimary)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var alignmentPreview: some View {
        ZStack(alignment: .topLeading) {
            DSColor.backgroundPrimary

            if let image = store.previewImage {
                LocalFloorPlanCanvas(
                    image: image,
                    mask: nil,
                    tool: store.tool,
                    normalizedDiameter: store.normalizedDiameter,
                    scaleA: store.startPlanPoint,
                    scaleB: store.directionPlanPoint,
                    scaleMarkerAppearance: .scanHeading,
                    usesTransparentBackground: true,
                    maximumInitialDisplaySize: CGSize(
                        width: maximumPreviewWidth,
                        height: maximumPreviewHeight
                    ),
                    imageToneOverlayOpacity: 0.2,
                    checkpointMarkers: preparationCheckpointMarkers,
                    checkpointAppearance: .plain,
                    layers: FloorPlanLayerDisplay(planOpacity: 1, maskOpacity: 0),
                    onStroke: { _ in },
                    onPoint: store.placePoint
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("floorPlan.alignment.canvas")
            }

            InstructorBackButton(action: handleTopBack)
                .disabled(!app.canGoBack)
                .padding(.top, DSSpacing.s40)
                .padding(.leading, DSSpacing.s40)

            DSGuideToast(alignmentGuideMessage)
                .frame(maxWidth: 690, minHeight: 100)
                .padding(.leading, 175)
                .padding(.trailing, DSSpacing.s40)
                .padding(.top, DSSpacing.s40)

            alignmentHistoryControls
                .padding(.leading, 40)
                .padding(.bottom, 41)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            statusOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 156)
                .padding(.trailing, 40)
        }
    }

    private var scanningPreview: some View {
        ZStack(alignment: .topLeading) {
            DSColor.backgroundPrimary

            if let image = store.previewImage {
                LocalFloorPlanCanvas(
                    image: image,
                    mask: nil,
                    tool: .move,
                    normalizedDiameter: store.normalizedDiameter,
                    scaleA: store.startPlanPoint,
                    scaleB: store.directionPlanPoint,
                    scaleMarkerAppearance: .scanHeading,
                    showsScanStartSelection: store.worldMapStart == nil,
                    usesTransparentBackground: true,
                    maximumInitialDisplaySize: CGSize(
                        width: maximumPreviewWidth,
                        height: maximumPreviewHeight
                    ),
                    imageToneOverlayOpacity: 0.2,
                    checkpointMarkers: scanningLocationMarkers,
                    checkpointAppearance: .plain,
                    layers: FloorPlanLayerDisplay(planOpacity: 1, maskOpacity: 0),
                    onStroke: { _ in },
                    onPoint: { _ in },
                    onCheckpointTap: scanCheckpointTapHandler
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("floorPlan.scanning.canvas")
            }

            InstructorBackButton(action: handleTopBack)
                .disabled(!app.canGoBack)
                .padding(.top, DSSpacing.s40)
                .padding(.leading, DSSpacing.s40)

            DSGuideToast(scanningGuideMessage)
                .frame(maxWidth: 690, minHeight: 100)
                .padding(.leading, 175)
                .padding(.trailing, DSSpacing.s40)
                .padding(.top, DSSpacing.s40)

            statusOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 156)
                .padding(.trailing, 40)
        }
    }

    private var alignmentHistoryControls: some View {
        HStack(spacing: 0) {
            alignmentHistoryButton(
                systemImage: "return",
                label: "체크포인트 실행 취소",
                enabled: store.canUndoWorldMapPoint,
                action: store.undoWorldMapPoint
            )
            alignmentHistoryButton(
                systemImage: "return.right",
                label: "체크포인트 다시 실행",
                enabled: store.canRedoWorldMapPoint,
                action: store.redoWorldMapPoint
            )
        }
        .frame(width: 194, height: 50)
        .background(DSColor.surfaceSelected)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(DSColor.surfaceSecondary, lineWidth: 1)
        }
    }

    private func alignmentHistoryButton(systemImage: String, label: String, enabled: Bool,
                                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .scaleEffect(y: -1)
                .foregroundStyle(DSColor.contentPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var informationPreview: some View {
        ZStack(alignment: .topLeading) {
            DSColor.backgroundPrimary

            informationImageContent
                .frame(maxWidth: maximumPreviewWidth, maxHeight: maximumPreviewHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            InstructorBackButton(action: handleTopBack)
                .disabled(isImportInteractionActive || !app.canGoBack)
                .padding(.top, DSSpacing.s40)
                .padding(.leading, DSSpacing.s40)

            statusOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(40)
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
    }

    @ViewBuilder
    private var informationImageContent: some View {
        if let image = store.previewImage {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .overlay(DSPalette.Gray.g700.opacity(0.2).allowsHitTesting(false))
                .accessibilityLabel("선택한 훈련장 도면")
                .accessibilityIdentifier("floorPlan.information.preview")
        }
    }

    private var editingRegistrationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("도면 설정")
                    .dsTextStyle(DSTypography.headingBold32)
                    .foregroundStyle(DSColor.contentPrimary)

                Spacer(minLength: 0)

                if !app.isEditingFloorPlan {
                InstructorStepIndicator(current: 4, total: 4)
                        .fixedSize()
                }
            }
            .padding(.top, 40)

            Text("벽 / 장애물 수정")
                .dsTextStyle(DSTypography.headingSemiBold20)
                .foregroundStyle(DSColor.contentPrimary)
                .padding(.top, 60)

            Text("자동 추출 결과를 확인하고, 정보를 수정하세요.")
                .dsTextStyle(DSTypography.bodyRegular16)
                .foregroundStyle(DSColor.contentTertiary)
                .padding(.top, 4)

            InstructorSegmentedControl(
                options: LocalFloorPlanEditorMode.allCases,
                selection: Binding(
                    get: { store.editorMode },
                    set: store.setEditorMode
                ),
                title: { mode in mode == .pen ? "펜툴" : "브러쉬" }
            )
            .padding(.top, 24)
            .accessibilityIdentifier("floorPlan.editing.tool")

            if store.editorMode == .pen {
                registrationPenControls
            } else {
                registrationBrushControls
            }

            Spacer(minLength: 24)

            HStack(spacing: 12) {
                Button(action: editingPreviousAction) {
                    Text("이전")
                        .frame(width: 92)
                }
                .buttonStyle(.dsSecondary)
                .accessibilityIdentifier("floorPlan.editing.previous")

                Button(action: editingSaveAction) {
                    Text(app.isUploadingFloorPlan ? "저장 중" : "도면 저장")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
                .frame(maxWidth: .infinity, minHeight: DSSize.controlHeight)
                .disabled(app.isEditingFloorPlan ? !store.canSaveMaskEdit : !store.canRegister)
                .accessibilityIdentifier(app.isEditingFloorPlan
                    ? "floorPlan.edit.save" : "floorPlan.save")
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.surfacePrimary)
    }

    private func editingPreviousAction() {
        if app.isEditingFloorPlan {
            app.goBack()
        } else {
            app.goBackFloorPlanCreationStep()
        }
    }

    private func editingSaveAction() {
        if app.isEditingFloorPlan {
            app.saveFloorPlanMaskEdit()
        } else {
            app.registerFloorPlan()
        }
    }

    private var registrationPenControls: some View {
        VStack(spacing: 0) {
            registrationEditButton("선택영역 추가하기", selected: true,
                                   enabled: true) {
                store.applySelection(.block)
            }

            registrationEditButton("선택영역 삭제하기", selected: true,
                                   enabled: true) {
                store.applySelection(.open)
            }
            .padding(.top, 20)

            InstructorLabeledSlider("원본 도면 투명도", value: planTransparency, step: 0.05)
                .padding(.top, 168)
                .accessibilityIdentifier("floorPlan.editing.planTransparency")
        }
        .padding(.top, 40)
    }

    private var registrationBrushControls: some View {
        VStack(spacing: 0) {
            registrationEditButton(
                "추가하기",
                selected: isRegistrationBrushAdding,
                enabled: !store.isProcessing
            ) {
                registrationBrushMode = .block
            }

            registrationEditButton(
                "지우기",
                selected: !isRegistrationBrushAdding,
                enabled: !store.isProcessing
            ) {
                registrationBrushMode = .open
            }
            .padding(.top, 20)

            brushSizePreview
                .padding(.top, 64)

            InstructorLabeledSlider(
                "브러쉬 크기",
                value: Binding(
                    get: { store.normalizedDiameter },
                    set: store.setBrushDiameter
                ),
                in: 0.001...0.05,
                step: 0.001,
                formatValue: { value in
                    guard let image = store.image else { return "–" }
                    let points = value * Double(min(image.width, image.height))
                    return "\(Int(points.rounded()))pt"
                }
            )
            .padding(.top, 32)
            .accessibilityIdentifier("floorPlan.editing.brushSize")

            InstructorLabeledSlider("원본 도면 투명도", value: planTransparency, step: 0.05)
                .padding(.top, 26)
                .accessibilityIdentifier("floorPlan.editing.planTransparency")
        }
        .padding(.top, 40)
    }

    /// The control expresses transparency, while the canvas stores image opacity.
    private var planTransparency: Binding<Double> {
        Binding(
            get: { 1 - layers.planOpacity },
            set: { layers.planOpacity = 1 - $0 }
        )
    }

    private func registrationEditButton(
        _ title: String,
        selected: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(InstructorSelectablePillStyle(isSelected: selected))
        .frame(maxWidth: .infinity, minHeight: 45)
        .disabled(!enabled)
    }

    private var isRegistrationBrushAdding: Bool {
        switch registrationBrushMode {
        case .block: true
        case .open: false
        }
    }

    private var brushSizePreview: some View {
        Canvas { context, size in
            let maximumVisibleLineWidth = max(1, min(size.width, size.height) - 4)
            let lineWidth = min(brushPreviewLineWidth, maximumVisibleLineWidth)
            let inset = lineWidth / 2 + 2
            let drawingRect = CGRect(origin: .zero, size: size)
                .insetBy(dx: inset, dy: inset)
            var path = Path()
            path.move(to: CGPoint(
                x: drawingRect.minX,
                y: drawingRect.minY + drawingRect.height * 0.68
            ))
            path.addCurve(
                to: CGPoint(
                    x: drawingRect.maxX,
                    y: drawingRect.minY + drawingRect.height * 0.28
                ),
                control1: CGPoint(
                    x: drawingRect.minX + drawingRect.width * 0.28,
                    y: drawingRect.minY
                ),
                control2: CGPoint(
                    x: drawingRect.minX + drawingRect.width * 0.62,
                    y: drawingRect.maxY
                )
            )
            context.stroke(
                path,
                with: .color(DSPalette.Red.r300),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .accessibilityHidden(true)
    }

    private var brushPreviewLineWidth: CGFloat {
        guard let image = store.image else { return 1 }
        let imageSpaceDiameter = CGFloat(store.normalizedDiameter)
            * CGFloat(min(image.width, image.height))
        return max(1, imageSpaceDiameter * editingCanvasDisplayScale)
    }

    private var editingGuideMessage: String {
        switch store.editorMode {
        case .pen:
            "필요한 영역을 점으로 찍어 선택하여 모양을 만든 후 추가/삭제 버튼으로 조작"
        case .brush:
            "추가/지우기 버튼을 먼저 누른 후 필요한 영역을 그리듯 조작"
        }
    }

    private var informationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("도면 설정")
                    .dsTextStyle(DSTypography.headingBold32)
                    .foregroundStyle(DSColor.contentPrimary)

                Spacer(minLength: 0)

                InstructorStepIndicator(current: 1, total: 4)
                    .fixedSize()
            }
            .padding(.top, 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("훈련장 이름 입력")
                    .dsTextStyle(DSTypography.headingSemiBold20)
                    .foregroundStyle(DSColor.contentPrimary)

                TextField(
                    "훈련장 A",
                    text: Binding(get: { store.name }, set: store.setName),
                    prompt: Text("훈련장 A").foregroundStyle(DSColor.contentTertiary)
                )
                .focused($focusedField, equals: .name)
                .keyboardType(.default)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .dsTextStyle(DSTypography.bodyRegular24)
                .foregroundStyle(DSColor.contentPrimary)
                .tint(DSColor.contentPrimary)
                .padding(.horizontal, 20)
                .frame(minHeight: 55)
                .background(DSColor.surfaceSecondary)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(informationNameBorderColor, lineWidth: informationNameBorderWidth)
                }
                .submitLabel(.next)
                .onSubmit(continueFromInformation)
                .onChange(of: store.name) { _, _ in
                    if store.hasName { showsNameValidation = false }
                }
                .onChange(of: focusedField) { previous, current in
                    if previous == .name, current != .name, !store.hasName {
                        showsNameValidation = true
                    }
                }
                .accessibilityIdentifier("floorPlan.name")

                if showsNameValidation, !store.hasName {
                    Text("훈련장 이름을 입력해주세요.")
                        .dsTextStyle(DSTypography.captionRegular14)
                        .foregroundStyle(DSColor.statusError)
                        .accessibilityIdentifier("floorPlan.name.validation")
                }
            }
            .padding(.top, 52)

            Spacer(minLength: 24)

            Button(action: continueFromInformation) {
                Text("다음")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsPrimary)
            .disabled(!store.canContinueToAlignment || isImportInteractionActive)
            .accessibilityIdentifier("floorPlan.next.alignment")
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.surfacePrimary)
    }

    private var informationNameBorderColor: Color {
        if showsNameValidation, !store.hasName { return DSColor.statusError }
        if focusedField == .name { return DSColor.contentPrimary }
        return DSColor.surfaceSecondary
    }

    private var informationNameBorderWidth: CGFloat {
        focusedField == .name || (showsNameValidation && !store.hasName) ? 2 : 1
    }

    private func continueFromInformation() {
        focusedField = nil
        guard store.hasName else {
            showsNameValidation = true
            return
        }
        guard store.canContinueToAlignment, !isImportInteractionActive else { return }
        store.continueToWorldMapAlignment()
    }

    private var alignmentPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("도면 설정")
                    .dsTextStyle(DSTypography.headingBold32)
                    .foregroundStyle(DSColor.contentPrimary)

                Spacer(minLength: 0)

                InstructorStepIndicator(current: 2, total: 4)
                    .fixedSize()
            }
            .padding(.top, 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("공간 스캔 사전 준비")
                    .dsTextStyle(DSTypography.headingSemiBold20)
                    .foregroundStyle(DSColor.contentPrimary)

                Text("정확도 높은 훈련 기록을 위해\n사전 카메라 공간 스캔이 필요합니다.")
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .fontWeight(.bold)
                    .foregroundStyle(DSColor.contentTertiary)
            }
            .padding(.top, 52)

            VStack(spacing: 12) {
                alignmentSettingCard(
                    title: "출발 방향",
                    status: alignmentReferenceStatus,
                    actionSystemImage: "arrow.counterclockwise",
                    actionAccessibilityLabel: "출발 방향 다시 설정",
                    action: store.resetWorldMapReference
                ) {
                    alignmentReferenceSymbol
                }

                alignmentSettingCard(
                    title: "체크포인트",
                    status: store.scanCheckpoints.isEmpty
                        ? "설정 필요" : "\(store.scanCheckpoints.count)개 설정됨",
                    actionSystemImage: "trash",
                    actionAccessibilityLabel: "체크포인트 전체 삭제",
                    actionEnabled: !store.scanCheckpoints.isEmpty,
                    action: store.clearScanCheckpoints
                ) {
                    Circle()
                        .fill(DSPalette.Red.r100)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.top, 24)

            Spacer(minLength: 24)

#if DEBUG && targetEnvironment(simulator)
            if store.canPreviewExtractedMask {
                Button(action: store.previewExtractedMask) {
                    Text("마스크만 확인")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsSecondary)
                .accessibilityHint("AR 공간 스캔 없이 자동 추출 마스크를 확인합니다.")
                .accessibilityIdentifier("floorPlan.simulator.maskPreview")
                .padding(.bottom, 12)
            }
#endif

            HStack(spacing: 12) {
                Button(action: app.goBackFloorPlanCreationStep) {
                    Text("이전")
                        .frame(width: 92)
                }
                .buttonStyle(.dsSecondary)
                .accessibilityIdentifier("floorPlan.previous.information")

                Button(action: {
                    Task { await store.proceedFromWorldMapAlignment() }
                }) {
                    Text(store.canReturnToEditingWithWorldMap ? "다음" : "스캔하기")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
                .frame(maxWidth: .infinity, minHeight: DSSize.controlHeight)
                .disabled(!store.canProceedFromWorldMapAlignment)
                .accessibilityIdentifier("floorPlan.scan.start")
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.surfacePrimary)
    }

    private var alignmentReferenceStatus: String {
        if store.startPlanPoint == nil { return "설정 필요" }
        if store.directionPlanPoint == nil { return "방향 설정 중" }
        return "설정 완료"
    }

    private var alignmentReferenceSymbol: some View {
        Canvas { context, size in
            let origin = CGPoint(x: 10, y: size.height / 2)
            let radius = max(1, size.width - origin.x)
            var fan = Path()
            fan.move(to: origin)
            fan.addArc(
                center: origin,
                radius: radius,
                startAngle: .degrees(-22),
                endAngle: .degrees(22),
                clockwise: false
            )
            fan.closeSubpath()
            context.fill(
                fan,
                with: .linearGradient(
                    Gradient(colors: [DSPalette.Red.r300, DSPalette.Red.r300.opacity(0.18)]),
                    startPoint: origin,
                    endPoint: CGPoint(x: size.width, y: origin.y)
                )
            )
            context.fill(
                Path(ellipseIn: CGRect(x: 2, y: origin.y - 8, width: 16, height: 16)),
                with: .color(DSPalette.Red.r400)
            )
        }
        .frame(width: 58, height: 44)
        .accessibilityHidden(true)
    }

    private func alignmentSettingCard<Symbol: View>(
        title: String,
        status: String,
        actionSystemImage: String,
        actionAccessibilityLabel: String,
        actionEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder symbol: () -> Symbol
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .dsTextStyle(DSTypography.headingSemiBold20)
                .foregroundStyle(DSColor.contentPrimary)

            HStack(spacing: 12) {
                symbol()
                    .frame(width: 58, height: 44)

                Text(status)
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .fontWeight(.bold)
                    .foregroundStyle(DSColor.contentPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(action: action) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 20, weight: .medium))
                }
                .buttonStyle(.dsCircular(size: .compact))
                .disabled(!actionEnabled)
                .accessibilityLabel(actionAccessibilityLabel)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surfaceSecondary)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var scanningPanel: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("도면 설정")
                        .dsTextStyle(DSTypography.headingBold32)
                        .foregroundStyle(DSColor.contentPrimary)

                    Spacer(minLength: 0)

                    InstructorStepIndicator(current: 3, total: 4)
                        .fixedSize()
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 0) {
                    Text("공간 스캔 중")
                        .dsTextStyle(DSTypography.headingSemiBold20)
                        .foregroundStyle(DSColor.contentPrimary)

                    Text("정확도 높은 훈련 기록을 위해\n사전 카메라 공간 스캔이 필요합니다.")
                        .dsTextStyle(DSTypography.bodyRegular16)
                        .fontWeight(.bold)
                        .foregroundStyle(DSColor.contentTertiary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(worldMapMappingIndicatorColor)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)

                        Text(store.frameState.mapping.message)
                            .dsTextStyle(DSTypography.captionRegular14)
                            .foregroundStyle(DSColor.contentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("현재 지점 스캔 상태")
                    .accessibilityValue(store.frameState.mapping.message)
                    .accessibilityIdentifier("floorPlan.scan.mappingStatus")
                }
                .padding(.top, 52)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(DSPalette.Red.r100)
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)

                        Text("체크포인트")
                            .dsTextStyle(DSTypography.bodyRegular16)
                            .fontWeight(.bold)

                        Spacer(minLength: 8)

                        Text("\(store.completedScanCheckpointCount) / \(store.scanCheckpoints.count) 완료")
                            .dsTextStyle(DSTypography.bodyRegular16)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(DSColor.contentPrimary)

                    Text("도면에서 체크포인트를 선택한 뒤 현재 위치를 기록하세요.")
                        .dsTextStyle(DSTypography.captionRegular14)
                        .foregroundStyle(DSColor.contentTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(DSColor.surfaceSecondary)
                .clipShape(.rect(cornerRadius: 12))
                .padding(.top, 20)
                .accessibilityIdentifier("floorPlan.scan.progress")

                Group {
                    if let session = store.worldMapPreviewSession {
                        LocalARWorldMapCameraView(previewSession: session)
                    } else {
                        Text("카메라 화면")
                            .dsTextStyle(DSTypography.headingSemiBold28)
                            .fontWeight(.bold)
                            .foregroundStyle(DSColor.contentDisabled)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(DSColor.contentSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: max(180, geometry.size.height / 2 - 248))
                .background(DSColor.contentSecondary)
                .clipShape(.rect(cornerRadius: 16))
                .padding(.top, 16)
                .accessibilityLabel("AR 공간 스캔 카메라")
                .accessibilityIdentifier("floorPlan.scan.camera")

                Spacer(minLength: 24)

                HStack(spacing: 12) {
                    Button(action: app.goBackFloorPlanCreationStep) {
                        Text("이전")
                            .frame(width: 92)
                    }
                    .buttonStyle(.dsSecondary)
                    .accessibilityIdentifier("floorPlan.scan.previous")

                    if store.worldMapStart == nil {
                        Button(action: store.captureWorldMapStart) {
                            Text("출발 위치 기록")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsPrimary)
                        .disabled(!store.canCaptureStartAlignment)
                        .accessibilityIdentifier("floorPlan.scan.captureStartLocation")
                    } else if store.completedScanCheckpointCount == store.scanCheckpoints.count {
                        Button(action: {
                            Task { await store.saveWorldMap() }
                        }) {
                            Text(store.isSavingWorldMap ? "공간 스캔 저장 중" : "다음")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsPrimary)
                        .disabled(!store.canSaveWorldMap)
                        .accessibilityIdentifier("floorPlan.scan.next")
                    } else {
                        Button(action: handleCheckpointCapture) {
                            Text("현재 위치 기록")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsPrimary)
                        .disabled(!store.canCaptureSelectedCheckpoint)
                        .accessibilityIdentifier("floorPlan.scan.captureCurrentLocation")
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.surfacePrimary)
    }

    private var alignmentGuideMessage: String {
        if store.startPlanPoint == nil {
            return "공간 스캔을 시작할 출발점을 도면 위에서 터치해 표시해주세요."
        }
        if store.directionPlanPoint == nil {
            return "출발점에서 처음 바라볼 방향점을 도면 위에서 터치해 표시해주세요."
        }
        return "방의 입구나 모서리, 복도의 연결부 등 공간의 특징점이 될만한 지점을 터치해 표시해주세요."
    }

    private var scanningGuideMessage: String {
        if !store.frameState.tracking.canCapture {
            return store.frameState.tracking.message
        }
        if store.worldMapStart == nil {
            return "출발점으로 이동해 방향 표시가 가리키는 곳을 바라본 후,\n출발 위치 기록 버튼을 눌러주세요."
        }
        if store.selectedScanCheckpointIndex != nil {
            return "선택한 체크포인트의 실제 위치에서\n현재 위치 기록 버튼을 눌러주세요."
        }
        if store.completedScanCheckpointCount < store.scanCheckpoints.count {
            return "미완료 체크포인트 위치로 이동 후,\n도면에서 기록할 체크포인트를 선택해주세요."
        }
        return "이동 시에 카메라가 가려지지 않고, 주변을 많이 촬영할수록 정확도를 높일 수 있습니다."
    }

    private var worldMapMappingIndicatorColor: Color {
        switch store.frameState.mapping {
        case .unavailable: InstructorColor.worldMapUnavailableIndicator
        case .limited: InstructorColor.worldMapLimitedIndicator
        case .extending: InstructorColor.worldMapExtendingIndicator
        case .mapped: InstructorColor.worldMapMappedIndicator
        }
    }

    private func handleTopBack() {
        focusedField = nil
        if app.isEditingFloorPlan {
            app.goBack()
        } else {
            showsExitConfirmation = true
        }
    }

    private func handleScanMarkerTap(_ markerIndex: Int) {
        store.selectScanCheckpoint(at: markerIndex)
    }

    private func handleCheckpointCapture() {
        store.captureSelectedScanCheckpoint()
    }

    private var alignmentInstruction: String {
        if store.startPlanPoint == nil {
            return "도면에서 실제 스캔을 시작할 위치를 탭하세요."
        }
        if store.directionPlanPoint == nil {
            return "출발 위치에서 처음 바라볼 방향을 도면 위에서 탭하세요."
        }
        return "공간 정보가 많은 지점을 체크포인트로 표시하세요. 스캔할 때 자유로운 순서로 방문할 수 있습니다."
    }

    private var scanProgressTitle: String {
        guard store.worldMapStart != nil else { return "시작 위치 맞추기" }
        return "체크포인트 \(store.completedScanCheckpointCount) / \(store.scanCheckpoints.count) 완료"
    }

    private func scanLegend(color: Color, title: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(title)
                .dsTextStyle(DSTypography.bodyRegular12)
                .foregroundStyle(InstructorColor.textPrimary)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if (store.step == .editing && store.isProcessing && !store.isReplayingEdits)
            || importer.isPreparing || store.errorMessage != nil || importer.message != nil
            || app.floorPlanUploadError != nil
            || store.canRetryMaskExtraction {
            VStack(alignment: .leading, spacing: 8) {
                if importer.isPreparing {
                    HStack {
                        ProgressView()
                        Text("파일 선택기를 준비하는 중")
                    }
                    .accessibilityIdentifier("floorPlan.import.preparing")
                }
                if store.step == .editing && store.isProcessing && !store.isReplayingEdits {
                    HStack {
                        ProgressView()
                        Text(store.activity)
                        Button("취소", action: store.cancelProcessing)
                    }
                    .accessibilityIdentifier("floorPlan.import.processing")
                }
                if store.canRetryMaskExtraction {
                    Text("마스크 분석이 중단되었습니다. 다시 시도할 수 있습니다.")
                        .foregroundStyle(InstructorColor.validationError)
                    ActionButton("마스크 분석 다시 시도", action: store.retryMaskExtraction)
                        .accessibilityIdentifier("floorPlan.mask.retry")
                }
                if let error = store.errorMessage {
                    Text(error)
                        .foregroundStyle(InstructorColor.validationError)
                        .accessibilityIdentifier("floorPlan.error")
                }
                if let message = importer.message {
                    Text(message).foregroundStyle(InstructorColor.validationError)
                }
                if let error = app.floorPlanUploadError {
                    Text(error)
                        .foregroundStyle(InstructorColor.validationError)
                        .accessibilityIdentifier("floorPlan.upload.error")
                    ActionButton("업로드 다시 시도", action: app.retryFloorPlanUpload)
                        .accessibilityIdentifier("floorPlan.upload.retry")
                }
            }
            .dsTextStyle(DSTypography.captionRegular14)
            .foregroundStyle(InstructorColor.textPrimary)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.small))
        }
    }

    private var floorPlanSavingOverlay: some View {
        FloorPlanSavingOverlay()
    }

    private static let mediumBodyFont: Font = {
        InstructorTypography.bodyMedium16.font
    }()
}

private struct FloorPlanSavingOverlay: View {
    var body: some View {
        ZStack {
            DSPalette.Neutral.black
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text("도면 저장 중")
                    .dsTextStyle(DSTypography.headingSemiBold24)
                    .foregroundStyle(DSPalette.Gray.g50)

                Text("도면 정보를 저장하고 있습니다.\n\n잠시만 기다려주세요.")
                    .dsTextStyle(DSTypography.bodyRegular16)
                    .foregroundStyle(DSPalette.Gray.g100)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .frame(width: 300, height: 185, alignment: .topLeading)
            .modifier(FloorPlanSavingGlassStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("floorPlan.uploading")
    }
}

private struct FloorPlanSavingGlassStyle: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 16)

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(InstructorColor.savingOverlaySurface),
                    in: shape
                )
                .shadow(color: DSPalette.Neutral.black.opacity(0.82), radius: 24, y: 8)
        } else {
            content
                .background(InstructorColor.savingOverlaySurface, in: shape)
                .overlay {
                    shape.stroke(DSPalette.Gray.g300.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: DSPalette.Neutral.white.opacity(0.14), radius: 0.5)
                .shadow(color: DSPalette.Neutral.white.opacity(0.10), radius: 0, x: 1.3)
                .shadow(color: DSPalette.Neutral.white.opacity(0.10), radius: 0, x: -1.3)
                .shadow(color: DSPalette.Neutral.black.opacity(0.82), radius: 24, y: 8)
        }
    }
}

#Preview("도면 저장 로딩") {
    FloorPlanSavingOverlay()
        .frame(width: 1_366, height: 1_024)
}

#Preview("도면 생성 · 파일 미첨부") {
    let app = InstructorStore()
    return FloorPlanCreateView()
        .environment(app)
        .environment(app.floorPlanDraft)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#if DEBUG
#Preview("AR 출발점 · 기록 전", traits: .landscapeLeft) {
    let draft = FloorPlanDraftStore.makeScanningPreview(hasCapturedStart: false)
    let app = InstructorStore(floorPlanDraft: draft)
    return FloorPlanCreateView()
        .environment(app)
        .environment(draft)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#Preview("AR 체크포인트 · 선택 및 기록 가능", traits: .landscapeLeft) {
    let draft = FloorPlanDraftStore.makeScanningPreview(selectedIndex: 1)
    let app = InstructorStore(floorPlanDraft: draft)
    return FloorPlanCreateView()
        .environment(app)
        .environment(draft)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#Preview("AR 체크포인트 · 추적 불안정", traits: .landscapeLeft) {
    let draft = FloorPlanDraftStore.makeScanningPreview(
        tracking: .insufficientFeatures,
        selectedIndex: 1
    )
    let app = InstructorStore(floorPlanDraft: draft)
    return FloorPlanCreateView()
        .environment(app)
        .environment(draft)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#Preview("AR 체크포인트 · 기록 완료", traits: .landscapeLeft) {
    let draft = FloorPlanDraftStore.makeScanningPreview(completedIndices: [0, 1, 2])
    let app = InstructorStore(floorPlanDraft: draft)
    return FloorPlanCreateView()
        .environment(app)
        .environment(draft)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}

#Preview("도면 생성 · 처리 오류", traits: .landscapeLeft) {
    let draft = FloorPlanDraftStore.makeScanningPreview(selectedIndex: 1)
    draft.reportImportFailure(NSError(
        domain: "FloorPlanStatusPreview",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "도면 이미지를 처리하지 못했습니다. 다시 시도해주세요."]
    ))
    let app = InstructorStore(floorPlanDraft: draft)
    return FloorPlanCreateView()
        .environment(app)
        .environment(draft)
        .frame(width: 1_366, height: 1_024)
        .preferredColorScheme(.dark)
}
#endif
