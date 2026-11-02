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
    @State private var scanFeedbackMessage: String?
    @State private var scanFeedbackID = UUID()
    @State private var registrationBrushMode: LocalEditMode = .block
    @State private var editingCanvasDisplayScale: CGFloat = 1
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable { case name, distance }

    private var isImportInteractionActive: Bool {
        importer.isPreparing || importer.isPresented || store.isImporting
    }

    private var scanCheckpointMarkers: [LocalScanCheckpointMarker] {
        store.scanCheckpoints.enumerated().map { index, point in
            let state: LocalScanCheckpointState = store.step == .scanning
                && store.completedScanCheckpointIndices.contains(index)
                ? .completed : .planned
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

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(
                referenceSidebarWidth,
                max(
                    minimumSidebarWidth,
                    proxy.size.width * referenceSidebarWidth / referenceScreenWidth
                )
            )

            Group {
                if store.step == .information, !app.isEditingFloorPlan {
                    informationStep(sidebarWidth: sidebarWidth)
                } else if store.step == .alignment, !app.isEditingFloorPlan {
                    alignmentStep(sidebarWidth: sidebarWidth)
                } else if store.step == .scanning, !app.isEditingFloorPlan {
                    scanningStep(sidebarWidth: sidebarWidth)
                } else if store.step == .editing {
                    editingStep(sidebarWidth: sidebarWidth)
                } else {
                    creationWorkspace
                }
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

    private var creationWorkspace: some View {
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
                .disabled(isImportInteractionActive || app.isUploadingFloorPlan
                    || app.floorPlanUploadError != nil)
        }
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
                    keepsWhiteImageBackground: true,
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

            FloorPlanBackButton(action: handleTopBack)
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

            FloorPlanBackButton(action: handleTopBack)
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
                    onScanStartTap: handleScanStartTap,
                    onCheckpointTap: handleScanMarkerTap
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("floorPlan.scanning.canvas")
            }

            FloorPlanBackButton(action: handleTopBack)
                .disabled(!app.canGoBack)
                .padding(.top, DSSpacing.s40)
                .padding(.leading, DSSpacing.s40)

            DSGuideToast(scanningGuideMessage)
                .frame(maxWidth: 690, minHeight: 100)
                .padding(.leading, 175)
                .padding(.trailing, DSSpacing.s40)
                .padding(.top, DSSpacing.s40)

            if let scanFeedbackMessage {
                DSGuideToast(scanFeedbackMessage, type: .compact)
                    .accessibilityIdentifier("floorPlan.scan.feedback")
                    .padding(.leading, 175)
                    .padding(.top, 152)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

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

            FloorPlanBackButton(action: handleTopBack)
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

    private var header: some View {
        HStack(spacing: 16) {
            InstructorBackButton(action: handleTopBack)
                .disabled(isImportInteractionActive || !app.canGoBack)

            Text(store.image?.fileName ?? "도면 설정")
                .font(DSTypography.h2)
                .foregroundStyle(InstructorColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            if !app.isEditingFloorPlan {
                ActionButton(
                    store.image == nil ? "파일 첨부" : "파일 변경",
                    tone: .secondary,
                    density: .file
                ) {
                    importer.request { focusedField = nil }
                }
                .disabled(isImportInteractionActive || store.isProcessing || store.isDrawing
                    || app.isUploadingFloorPlan || app.floorPlanUploadError != nil)
                .accessibilityIdentifier("floorPlan.import")
            }
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
                mask: store.step == .editing ? store.maskImage : nil,
                tool: store.tool,
                normalizedDiameter: store.normalizedDiameter,
                selection: store.selection,
                pendingBrushStrokes: store.pendingBrushStrokes,
                scaleA: store.step == .alignment || store.step == .scanning
                    ? store.startPlanPoint : nil,
                scaleB: store.step == .alignment || store.step == .scanning
                    ? store.directionPlanPoint : nil,
                scaleLabel: nil,
                scaleALabel: "출발",
                scaleBLabel: "방향",
                checkpointMarkers: store.step == .alignment || store.step == .scanning
                    ? scanCheckpointMarkers : [],
                importPresentation: importer,
                layers: layers,
                onStroke: store.stageBrushStroke,
                onPoint: store.placePoint,
                onScaleMarkerMoved: store.moveScaleMarker,
                onEditingChanged: store.setDrawing
            )
            .allowsHitTesting(!store.isImporting && store.processingStage != .preparingPreview
                && !app.isUploadingFloorPlan
                && app.floorPlanUploadError == nil)
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
            switch store.step {
            case .information: informationPanel
            case .alignment: alignmentPanel
            case .scanning: scanningPanel
            case .editing: editingPanel
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
                    Text("이동 불가 영역 편집")
                        .font(DSTypography.h2)
                        .foregroundStyle(InstructorColor.textPrimary)

                    Text("자동으로 표시된 결과에서 잘못된 부분을 추가하거나 지우세요")
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

            ActionButton(
                app.isEditingFloorPlan
                    ? (app.isUploadingFloorPlan ? "수정본 업로드 중" : "수정 완료")
                    : (app.isUploadingFloorPlan ? "저장 중" : "도면 저장"),
                fillsWidth: true,
                action: app.isEditingFloorPlan ? app.saveFloorPlanMaskEdit : app.registerFloorPlan
            )
                .frame(height: 52)
                .disabled(app.isEditingFloorPlan ? !store.canSaveMaskEdit : !store.canRegister)
                .accessibilityIdentifier(app.isEditingFloorPlan
                    ? "floorPlan.edit.save" : "floorPlan.save")
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
        .disabled(store.image == nil || store.isProcessing || importer.isPreparing || importer.isPresented
            || app.isUploadingFloorPlan || app.floorPlanUploadError != nil)
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
            Text("수정할 영역을 점으로 찍어 선택하세요")
                .font(DSTypography.bodySmall)
                .foregroundStyle(InstructorColor.textPrimary)

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

    private var editingRegistrationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("도면 설정")
                    .dsTextStyle(DSTypography.headingBold32)
                    .foregroundStyle(DSColor.contentPrimary)

                Spacer(minLength: 0)

                DSStepIndicator(current: 4, total: 4)
                    .fixedSize()
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

            DSSegmentedControl(
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

            DSLabeledSlider("원본 도면 투명도", value: planTransparency, step: 0.05)
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

            DSLabeledSlider(
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

            DSLabeledSlider("원본 도면 투명도", value: planTransparency, step: 0.05)
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
        .buttonStyle(DSSelectablePillStyle(isSelected: selected))
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
            let lineWidth = brushPreviewLineWidth
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

                DSStepIndicator(current: 1, total: 4)
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

                DSStepIndicator(current: 2, total: 4)
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

                    DSStepIndicator(current: 3, total: 4)
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

                    Text("미완료 점 위치로 이동해 주변을 촬영한 뒤, 도면의 해당 점을 탭하세요.")
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

                    Button(action: {
                        Task { await store.saveWorldMap() }
                    }) {
                        Text("다음")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                    .disabled(!store.canSaveWorldMap)
                    .accessibilityIdentifier("floorPlan.scan.next")
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
        if store.worldMapStart == nil, store.frameState.trackingMessage == "추적 정상" {
            return "출발점으로 이동해 방향 표시가 가리키는 곳을 바라본 후,\n도면의 출발점을 클릭해 스캔 정보를 저장합니다."
        }
        if store.completedScanCheckpointCount < store.scanCheckpoints.count,
           store.frameState.trackingMessage == "추적 정상" {
            return "미완료 체크포인트 위치로 이동 후,\n도면의 해당 지점을 클릭해 스캔 정보를 저장합니다."
        }
        return "이동 시에 카메라가 가려지지 않고, 주변을 많이 촬영할수록 정확도를 높일 수 있습니다."
    }

    private func handleTopBack() {
        focusedField = nil
        if app.isEditingFloorPlan {
            app.goBack()
        } else {
            showsExitConfirmation = true
        }
    }

    private func handleScanStartTap() {
        guard store.worldMapStart == nil else {
            showScanFeedback("출발 위치의 스캔 정보가 이미 저장되었습니다.")
            return
        }
        guard store.frameState.trackingMessage == "추적 정상" else {
            showScanFeedback("주변을 천천히 촬영해 카메라 추적을 안정시켜주세요.")
            return
        }
        store.captureWorldMapStart()
        if store.worldMapStart != nil {
            showScanFeedback("출발 위치와 방향을 저장했습니다. 이제 체크포인트로 이동해주세요.")
        }
    }

    private func handleScanMarkerTap(_ markerIndex: Int) {
        switch store.captureScanCheckpoint(at: markerIndex) {
        case .captured:
            showScanFeedback("체크포인트의 스캔 정보를 저장했습니다.")
        case .startRequired:
            showScanFeedback("먼저 출발 위치로 이동해 도면의 출발점을 탭해주세요.")
        case .trackingUnavailable:
            showScanFeedback("주변을 천천히 촬영해 카메라 추적을 안정시켜주세요.")
        case .alreadyCaptured:
            showScanFeedback("이미 스캔 정보를 저장한 체크포인트입니다.")
        case .invalidCheckpoint:
            showScanFeedback("선택한 체크포인트를 확인할 수 없습니다.")
        case .failed(let message):
            showScanFeedback(message)
        }
    }

    private func showScanFeedback(_ message: String) {
        let feedbackID = UUID()
        scanFeedbackID = feedbackID
        withAnimation(.easeOut(duration: 0.2)) {
            scanFeedbackMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard scanFeedbackID == feedbackID else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                scanFeedbackMessage = nil
            }
        }
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
                .font(DSTypography.caption)
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
            .font(DSTypography.bodySmall)
            .foregroundStyle(InstructorColor.textPrimary)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private var floorPlanSavingOverlay: some View {
        FloorPlanSavingOverlay()
    }

    private static let mediumBodyFont: Font = {
        DSFonts.register()
        return .custom("NotoSansKR-Medium", size: 16, relativeTo: .body)
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
