import SwiftUI
import UniformTypeIdentifiers

struct FloorPlanCreateView: View {
    @Environment(InstructorStore.self) private var app
    @Environment(FloorPlanDraftStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 12) {
            Text("파일 선택 → 장애물·외곽 편집 → 축척 → 확인·등록").font(.subheadline)
            layout {
                ScrollView { controls.padding().frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxWidth: sizeClass == .compact ? .infinity : 340)
                canvas.frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 300)
            }
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.red).font(.callout).accessibilityIdentifier("floorPlan.error")
            }
            if store.isProcessing {
                HStack {
                    ProgressView()
                    Text(store.activity)
                    ActionButton("처리 취소", action: store.cancelProcessing)
                }
            }
            footer
        }
        .padding()
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.png, .jpeg]) { result in
            switch result {
            case .success(let url): store.importImage(from: url)
            case .failure(let error): store.reportImportFailure(error)
            }
        }
    }

    private var layout: AnyLayout {
        sizeClass == .compact ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("도면 이름").font(.headline)
            TextField("훈련장 이름", text: Binding(get: { store.name }, set: store.setName))
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("floorPlan.name")
            ActionButton(store.image == nil ? "도면 파일 선택" : "다른 파일 선택") { showingImporter = true }
                .disabled(store.isProcessing || store.isDrawing).accessibilityIdentifier("floorPlan.import")
            Text(store.image?.fileName ?? "PNG 또는 JPEG · 최대 40 MiB").font(.caption).foregroundStyle(.secondary)
            if let image = store.image {
                Text("처리 이미지: \(image.width) × \(image.height) px").font(.caption)
            }
            Divider()
            switch store.step {
            case .information:
                Text("도면을 선택하면 장애물 초안을 자동 추출합니다. 이후 통로와 외곽을 직접 확인해주세요.")
            case .editing: editingControls
            case .scaling: scaleControls
            case .reviewing: reviewControls
            }
        }
    }

    private var editingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("장애물·외곽 편집").font(.title3)
            Text("보라색은 통과 불가 영역입니다. 자동 추출은 초안이며 문·가구·문자를 검수해주세요.").font(.caption)
            HStack { toolButton("이동", .move); toolButton("막기", .block); toolButton("열기", .open) }
            Text("붓 지름: 짧은 변의 \(store.normalizedDiameter * 100, specifier: "%.1f")%").font(.caption)
            Slider(value: Binding(get: { store.normalizedDiameter }, set: store.setBrushDiameter), in: 0.001...0.05)
                .accessibilityLabel("브러시 굵기")
            HStack {
                ActionButton("획 되돌리기", action: store.undoStroke).disabled(store.strokes.isEmpty)
                ActionButton("편집 초기화", action: store.resetEdits).disabled(store.strokes.isEmpty)
            }
            Divider()
            Text("실내 외곽").font(.headline)
            Text("유효한 실내 영역의 꼭짓점을 순서대로 누르고 외곽을 확정하세요.").font(.caption)
            toolButton("외곽 점 찍기", .outline)
            HStack {
                ActionButton("한 점 취소", action: store.undoOutlinePoint).disabled(store.outline.isEmpty)
                ActionButton("외곽 초기화", action: store.resetOutline)
            }
            ActionButton(store.outlineConfirmed ? "외곽 확정됨" : "외곽 확정", action: store.confirmOutline)
                .disabled(store.outline.count < 3 || store.outlineConfirmed)
                .accessibilityIdentifier("floorPlan.outline.confirm")
            Text("\(store.outline.count)개 꼭짓점 · 외곽 밖은 열기 도구로 열 수 없습니다.").font(.caption)
            Text("Pencil·한 손가락: 편집 / 두 손가락: 이동·확대").font(.caption).foregroundStyle(.secondary)
            if store.resolvedGrid == nil && !store.isProcessing {
                ActionButton("미리보기 다시 계산", action: store.refreshMask)
            }
        }
        .disabled(store.isProcessing || store.isDrawing)
    }

    private var scaleControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("축척 설정").font(.title3)
            Text("도면에서 실제 거리를 아는 두 점을 선택하세요. A 선택 후 B를 지정합니다.")
            HStack { toolButton("A 지정", .scaleA); toolButton("B 지정", .scaleB) }
            Text("A: \(store.scaleA == nil ? "미지정" : "지정됨") / B: \(store.scaleB == nil ? "미지정" : "지정됨")").font(.caption)
            TextField("실제 거리 (m)", text: Binding(get: { store.distanceText }, set: store.setDistance))
                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityIdentifier("floorPlan.distance")
            Text("두 점 간 10px 이상 · 거리 0 초과 1000m 이하").font(.caption)
            if let value = store.pixelsPerMeter { Text("1m = \(value, specifier: "%.2f") px") }
            ActionButton("장애물 편집으로", action: store.returnToEditing)
        }
    }

    private var reviewControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("최종 확인").font(.title3)
            Text("원본 도면과 보라색 장애물, 문·통로, 실내 외곽, 기준 거리를 확인해주세요.")
            Text("수동 편집 \(store.strokes.count)획 · 외곽 \(store.outline.count)점")
            Text("기준 거리 \(store.scale?.meters ?? 0, specifier: "%.2f") m")
            Toggle("최종 장애물과 축척을 확인했습니다", isOn: Binding(get: { store.reviewed }, set: store.setReviewed))
                .accessibilityIdentifier("floorPlan.reviewed")
            ActionButton("축척 다시 설정", action: store.returnToScale)
            ActionButton("장애물 다시 편집", action: store.returnToEditing)
        }
    }

    private func toolButton(_ title: String, _ tool: LocalCanvasTool) -> some View {
        ActionButton(title, action: { store.setTool(tool) })
        .fontWeight(store.tool == tool ? .bold : .regular)
        .accessibilityAddTraits(store.tool == tool ? .isSelected : [])
        .accessibilityIdentifier("floorPlan.tool.\(tool.rawValue)")
    }

    @ViewBuilder private var canvas: some View {
        if let image = store.previewImage {
            LocalFloorPlanCanvas(image: image, mask: store.maskImage, tool: store.tool,
                normalizedDiameter: store.normalizedDiameter, outline: store.outline,
                scaleA: store.scaleA, scaleB: store.scaleB,
                scaleLabel: store.pixelsPerMeter == nil ? nil : store.scale.map { String(format: "%.2f m", $0.meters) },
                onStroke: store.appendStroke, onPoint: store.placePoint, onEditingChanged: store.setDrawing)
                .allowsHitTesting(!store.isProcessing).accessibilityIdentifier("floorPlan.canvas")
        } else {
            ContentUnavailableView("도면 파일을 선택하세요", systemImage: "map",
                description: Text("선택한 이미지와 장애물을 여기에서 확인합니다."))
        }
    }

    private var footer: some View {
        HStack {
            Text("임시 등록 · 앱 종료 시 사라집니다").font(.caption).foregroundStyle(.secondary)
            Spacer()
            switch store.step {
            case .information: EmptyView()
            case .editing:
                ActionButton("축척 설정으로", action: store.continueToScale).disabled(!store.canContinueEditing)
                    .accessibilityIdentifier("floorPlan.next.scale")
            case .scaling:
                ActionButton("최종 확인", action: store.showReview).disabled(!store.canReview)
                    .accessibilityIdentifier("floorPlan.next.review")
            case .reviewing:
                ActionButton("도면 등록", action: app.registerFloorPlan).disabled(!store.canRegister)
                    .accessibilityIdentifier("floorPlan.save")
            }
        }
    }
}

#Preview {
    let app = InstructorStore()
    return FloorPlanCreateView().environment(app).environment(app.floorPlanDraft)
}
