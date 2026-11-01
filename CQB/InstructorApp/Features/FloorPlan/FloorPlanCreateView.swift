import CQBDesignSystem
import CQBCore
import SwiftUI
import UniformTypeIdentifiers

struct FloorPlanCreateView: View {
    @Environment(InstructorStore.self) private var app
    @Environment(FloorPlanDraftStore.self) private var store
    @State private var importer = FloorPlanImportPresentation()
    @State private var layers = FloorPlanLayerDisplay(planOpacity: 0.5, maskOpacity: 0.5)
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable { case name, distance }

    private var isImportInteractionActive: Bool {
        importer.isPreparing || importer.isPresented || store.isImporting
    }

    private var scanCheckpointMarkers: [LocalScanCheckpointMarker] {
        store.scanCheckpoints.enumerated().map { index, point in
            let state: LocalScanCheckpointState
            if store.step == .scanning, index < store.completedScanCheckpointCount {
                state = .completed
            } else if store.step == .scanning, index == store.currentScanCheckpointIndex {
                state = .current
            } else {
                state = .planned
            }
            return LocalScanCheckpointMarker(point: point, number: index + 1, state: state)
        }
    }

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
                .disabled(isImportInteractionActive || app.isUploadingFloorPlan
                    || app.floorPlanUploadError != nil)
        }
        .background(InstructorColor.canvas.ignoresSafeArea())
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
        .onDisappear { importer.finish() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            InstructorBackButton(action: app.goBack)
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

    private var informationPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("도면 정보")
                        .font(DSTypography.h2)
                        .foregroundStyle(InstructorColor.textPrimary)

                    Text("도면 이미지를 첨부하고 이름을 입력하세요. 이미지 분석은 다음 단계와 병렬로 진행됩니다.")
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(InstructorColor.textSecondary)
                        .padding(.top, 8)

                    Text("도면 이름 설정")
                        .font(DSTypography.h2)
                        .foregroundStyle(InstructorColor.textPrimary)
                        .padding(.top, 40)

                    TextField(
                        "훈련장 A",
                        text: Binding(get: { store.name }, set: store.setName),
                        prompt: Text("훈련장 A").foregroundStyle(InstructorColor.textSecondary)
                    )
                    .focused($focusedField, equals: .name)
                    .keyboardType(.default)
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

            ActionButton("다음", fillsWidth: true, action: store.continueToWorldMapAlignment)
                .frame(height: 52)
                .disabled(!store.canContinueToAlignment || isImportInteractionActive)
                .accessibilityIdentifier("floorPlan.next.alignment")
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
        }
    }

    private var alignmentPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("스캔 기준 설정")
                        .font(DSTypography.h2)

                    Text(alignmentInstruction)
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(InstructorColor.textSecondary)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        scanLegend(color: .red, title: "출발 위치 · 바라보는 방향")
                        scanLegend(color: .blue, title: "추가 스캔 체크포인트")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(InstructorColor.surfaceRaised)
                    .clipShape(.rect(cornerRadius: 4))
                    .padding(.top, 24)

                    if store.directionPlanPoint != nil {
                        Text("체크포인트 \(store.scanCheckpoints.count)개")
                            .font(DSTypography.bodySmall)
                            .foregroundStyle(InstructorColor.textPrimary)
                            .padding(.top, 24)

                        panelButton("마지막 체크포인트 삭제", enabled: !store.scanCheckpoints.isEmpty) {
                            store.removeLastScanCheckpoint()
                        }
                        .padding(.top, 12)
                    }

                    if store.startPlanPoint != nil {
                        panelButton("출발·방향 다시 설정", enabled: true) {
                            store.resetWorldMapReference()
                        }
                        .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            ActionButton("AR 스캔 시작", fillsWidth: true) {
                Task { await store.startWorldMapScan() }
            }
            .frame(height: 52)
            .disabled(!store.canStartWorldMapScan)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private var scanningPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("공간 스캔")
                        .font(DSTypography.h2)

                    Text(scanProgressTitle)
                        .font(DSTypography.h3)
                        .foregroundStyle(InstructorColor.actionPrimary)
                        .padding(.top, 16)

                    Text("\(store.frameState.mapping.title) · \(store.frameState.trackingMessage)")
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(InstructorColor.textSecondary)
                        .padding(.top, 4)

                    if let session = store.worldMapPreviewSession {
                        LocalARWorldMapCameraView(previewSession: session)
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 4))
                            .padding(.top, 20)
                    }

                    if store.worldMapStart == nil {
                        Text("도면의 출발점과 같은 실제 위치에서 방향점을 바라본 뒤 시작 자세를 저장하세요.")
                            .font(DSTypography.caption)
                            .foregroundStyle(InstructorColor.textSecondary)
                            .padding(.top, 16)
                        panelButton("시작 자세 저장", enabled: store.canCaptureStartAlignment) {
                            store.captureWorldMapStart()
                        }
                        .padding(.top, 12)
                    } else if let index = store.currentScanCheckpointIndex {
                        Text("도면에서 노란색으로 표시된 체크포인트 \(index + 1)의 실제 위치로 이동해 주변을 천천히 비춘 뒤 기록하세요.")
                            .font(DSTypography.bodySmall)
                            .foregroundStyle(InstructorColor.textSecondary)
                            .padding(.top, 16)
                        panelButton("이 위치 기록", enabled: store.canCaptureScanCheckpoint) {
                            store.captureCurrentScanCheckpoint()
                        }
                        .padding(.top, 12)
                    } else {
                        Text(store.frameState.mapping == .mapped
                            ? "모든 체크포인트 기록이 완료되었습니다. 스캔을 완료할 수 있습니다."
                            : "모든 체크포인트를 기록했습니다. 주변을 천천히 비추며 공간 정보를 조금 더 수집하세요.")
                            .font(DSTypography.bodySmall)
                            .foregroundStyle(InstructorColor.textSecondary)
                            .padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            ActionButton(store.isSavingWorldMap ? "WorldMap 저장 중" : "스캔 완료", fillsWidth: true) {
                Task { await store.saveWorldMap() }
            }
            .frame(height: 52)
            .disabled(!store.canSaveWorldMap)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private var alignmentInstruction: String {
        if store.startPlanPoint == nil {
            return "도면에서 실제 스캔을 시작할 위치를 탭하세요."
        }
        if store.directionPlanPoint == nil {
            return "출발 위치에서 처음 바라볼 방향을 도면 위에서 탭하세요."
        }
        return "공간 정보가 많은 지점을 체크포인트로 표시하세요. 스캔할 때 번호 순서대로 안내합니다."
    }

    private var scanProgressTitle: String {
        guard store.worldMapStart != nil else { return "시작 위치 맞추기" }
        if let index = store.currentScanCheckpointIndex {
            return "체크포인트 \(index + 1) / \(store.scanCheckpoints.count)"
        }
        return "체크포인트 \(store.scanCheckpoints.count) / \(store.scanCheckpoints.count)"
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
            || app.isUploadingFloorPlan || app.floorPlanUploadError != nil {
            VStack(alignment: .leading, spacing: 8) {
                if importer.isPreparing {
                    HStack {
                        ProgressView()
                        Text("파일 선택기를 준비하는 중")
                    }
                    .accessibilityIdentifier("floorPlan.import.preparing")
                }
                if app.isUploadingFloorPlan {
                    HStack {
                        ProgressView()
                        Text(app.isEditingFloorPlan
                            ? "수정된 마스크를 새 도면 버전으로 업로드하는 중"
                            : "도면 파일 3개를 Storage에 업로드하는 중")
                    }
                    .accessibilityIdentifier("floorPlan.uploading")
                }
                if store.step == .editing && store.isProcessing && !store.isReplayingEdits {
                    HStack {
                        ProgressView()
                        Text(store.activity)
                        Button("취소", action: store.cancelProcessing)
                    }
                    .accessibilityIdentifier("floorPlan.import.processing")
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
