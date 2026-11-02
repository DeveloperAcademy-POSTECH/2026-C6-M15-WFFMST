import CQBCore
import CQBDesignSystem
import SwiftUI
import UIKit

struct AARMovementView: View {
    @Environment(InstructorStore.self) private var store
    @Environment(AARStore.self) private var aarStore
    @State private var gestureStartViewport: AARFloorPlanViewport?

    // Figma(노드 762:3230 map canvas): 도면은 여백 없이 영역에 비율을 유지해 맞춘다.
    private let floorPlanPadding: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(InstructorColor.surfaceBase)

                if let imageSize = aarStore.floorPlanImageSize {
                    let layout = AARFloorPlanLayout(
                        imageSize: imageSize,
                        container: geometry.size,
                        padding: floorPlanPadding
                    )
                    viewportContent(layout: layout, container: geometry.size)
                } else {
                    floorPlanUnavailableState
                }
            }
            .overlay(alignment: .topTrailing) {
                unavailablePositionArea
                    .padding(12)
            }
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
            }
        }
        .accessibilityValue("도면 확대 \(store.aarFloorPlanViewport.scale.formatted())배")
        .accessibilityIdentifier("aar.movement")
    }

    private func viewportContent(
        layout: AARFloorPlanLayout,
        container: CGSize
    ) -> some View {
        let viewport = store.aarFloorPlanViewport

        return ZStack {
            floorPlanImage(layout: layout, viewport: viewport)

            ForEach(store.aarParticipants) { participant in
                if let position = aarStore.position(for: participant.id) {
                    Button {
                        store.toggleParticipantSelection(participant.id)
                    } label: {
                        participantMarker(
                            participant,
                            showsName: viewport.showsParticipantNames
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(position.presence == .tracked ? 1 : 0.35)
                    .position(viewport.viewPoint(for: position.point, layout: layout))
                    .accessibilityLabel(markerAccessibilityLabel(participant))
                    .accessibilityHint(store.isParticipantSelected(participant.id)
                        ? "선택을 해제합니다"
                        : "영상 패널에 추가합니다")
                    .accessibilityIdentifier("aar.marker.\(participant.id)")
                }
            }
        }
        .frame(width: container.width, height: container.height)
        .contentShape(.rect)
        .background {
            AARViewportGestureAnchor { update in
                updateViewport(update, layout: layout, container: container)
            }
        }
    }

    private func updateViewport(
        _ update: AARViewportGestureUpdate,
        layout: AARFloorPlanLayout,
        container: CGSize
    ) {
        if update.phase == .began {
            gestureStartViewport = store.aarFloorPlanViewport
        }
        guard let startViewport = gestureStartViewport else { return }

        let viewport = startViewport.applying(
            magnification: update.magnification,
            anchor: update.startLocation,
            drag: CGSize(
                width: update.location.x - update.startLocation.x,
                height: update.location.y - update.startLocation.y
            ),
            layout: layout,
            container: container
        )
        store.updateAARFloorPlanViewport(
            scale: viewport.scale,
            translation: viewport.translation,
            layout: layout,
            container: container
        )

        if update.phase == .ended {
            gestureStartViewport = nil
        }
    }

    @ViewBuilder
    private var unavailablePositionArea: some View {
        let participants = participantsWithoutPosition
        if !participants.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("위치 확인 불가", systemImage: "location.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(InstructorColor.textSecondary)

                ForEach(participants) { participant in
                    Button {
                        store.toggleParticipantSelection(participant.id)
                    } label: {
                        HStack(spacing: 4) {
                            participantMarker(participant, showsName: false)
                                .opacity(0.35)
                            Text(participant.displayName)
                                .font(.caption)
                                .foregroundStyle(InstructorColor.textSecondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(markerAccessibilityLabel(participant))
                    .accessibilityHint(store.isParticipantSelected(participant.id)
                        ? "선택을 해제합니다"
                        : "영상 패널에 추가합니다")
                    .accessibilityIdentifier("aar.marker.unavailable.\(participant.id)")
                }
            }
            .padding(12)
            .background(InstructorColor.surfaceRaised.opacity(0.94))
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(InstructorColor.borderDefault, lineWidth: 1)
            }
            .accessibilityIdentifier("aar.unavailablePositions")
        }
    }

    private var participantsWithoutPosition: [InstructorParticipant] {
        store.aarParticipants.filter { participant in
            aarStore.hasNoTrackPosition(for: participant.id)
                || aarStore.isFloorPlanUnavailable
        }
    }

    @ViewBuilder
    private func floorPlanImage(
        layout: AARFloorPlanLayout,
        viewport: AARFloorPlanViewport
    ) -> some View {
        if let image = aarStore.floorPlanImage ?? store.selectedPlanImage {
            Image(uiImage: image)
                .resizable()
                .frame(width: layout.imageFrame.width, height: layout.imageFrame.height)
                .scaleEffect(viewport.scale)
                .offset(viewport.translation)
                .opacity(0.5)
                .accessibilityLabel("선택한 훈련 도면")
        } else {
            floorPlanUnavailableState
        }
    }

    @ViewBuilder
    private var floorPlanUnavailableState: some View {
        if aarStore.isLoading {
            ProgressView("도면과 동선을 불러오는 중")
                .foregroundStyle(InstructorColor.textSecondary)
        } else {
            ContentUnavailableView(
                "도면 미리보기 없음",
                systemImage: "map",
                description: Text("선택한 훈련 도면을 불러오지 못했습니다.")
            )
            .foregroundStyle(InstructorColor.textSecondary)
        }
    }

    private func participantMarker(
        _ participant: InstructorParticipant,
        showsName: Bool
    ) -> some View {
        let slotNumber = store.videoSlotNumber(for: participant.id)

        return ZStack {
            Circle()
                .fill(slotNumber == nil ? InstructorColor.playerSurface : InstructorColor.actionPrimary)
                .frame(width: slotNumber == nil ? 18 : 48, height: slotNumber == nil ? 18 : 48)
                .overlay {
                    Circle()
                        .strokeBorder(InstructorColor.textPrimary, lineWidth: slotNumber == nil ? 2 : 0)
                }

            if let slotNumber {
                Text("\(slotNumber)")
                    .font(markerFont)
                    .foregroundStyle(InstructorColor.playerSurface)
                    .monospacedDigit()
            }
        }
        .frame(width: 48, height: 48)
        .contentShape(.circle)
        .overlay(alignment: .top) {
            if showsName {
                Text(participant.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(InstructorColor.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(InstructorColor.surfaceRaised.opacity(0.94))
                    .clipShape(.capsule)
                    .offset(y: -32)
                    .allowsHitTesting(false)
            }
        }
    }

    private func markerAccessibilityLabel(_ participant: InstructorParticipant) -> String {
        if let slotNumber = store.videoSlotNumber(for: participant.id) {
            return "\(participant.name), 선택됨, 영상 \(slotNumber)번"
        }
        return "\(participant.name), 선택되지 않음"
    }

    private var markerFont: Font {
        DSFonts.register()
        return .custom("NotoSansKR-Bold", size: 14, relativeTo: .body)
    }
}

private struct AARViewportGestureUpdate {
    enum Phase { case began, changed, ended }

    let phase: Phase
    let magnification: CGFloat
    let startLocation: CGPoint
    let location: CGPoint
}

/// UIKit에서 1-finger pan과 pinch를 분리해 한 물리 제스처를 한 번만 뷰포트에 반영한다.
private struct AARViewportGestureAnchor: UIViewRepresentable {
    let onUpdate: (AARViewportGestureUpdate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onUpdate: onUpdate) }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = context.coordinator.attach
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.onUpdate = onUpdate
        context.coordinator.anchorView = uiView
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class AnchorView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onWindowChange?(self.window)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onUpdate: (AARViewportGestureUpdate) -> Void
        weak var anchorView: UIView?
        private weak var window: UIWindow?
        private var pinchStartLocation = CGPoint.zero
        private var lastPinchLocation = CGPoint.zero
        private var lastPinchMagnification: CGFloat = 1
        private var panStartLocation = CGPoint.zero
        private var isPinching = false
        private var isPanning = false
        private lazy var pinchRecognizer: UIPinchGestureRecognizer = {
            let recognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()
        private lazy var panRecognizer: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            recognizer.minimumNumberOfTouches = 1
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        init(onUpdate: @escaping (AARViewportGestureUpdate) -> Void) {
            self.onUpdate = onUpdate
        }

        func attach(to window: UIWindow?) {
            guard self.window !== window else { return }
            detach()
            guard let window else { return }
            window.addGestureRecognizer(pinchRecognizer)
            window.addGestureRecognizer(panRecognizer)
            self.window = window
        }

        func detach() {
            window?.removeGestureRecognizer(pinchRecognizer)
            window?.removeGestureRecognizer(panRecognizer)
            isPinching = false
            isPanning = false
            panRecognizer.isEnabled = true
            window = nil
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let anchorView else { return }
            let location = recognizer.location(in: anchorView)
            switch recognizer.state {
            case .began:
                // 첫 손가락부터 추적하던 pan을 reset해 pinch 종료 후 남은 손가락이
                // 같은 터치 시퀀스의 드래그로 이어지지 않게 한다.
                panRecognizer.isEnabled = false
                isPinching = true
                pinchStartLocation = location
                lastPinchLocation = location
                lastPinchMagnification = recognizer.scale
                onUpdate(.init(
                    phase: .began,
                    magnification: recognizer.scale,
                    startLocation: pinchStartLocation,
                    location: location
                ))
            case .changed:
                guard isPinching, recognizer.numberOfTouches >= 2 else { return }
                lastPinchLocation = location
                lastPinchMagnification = recognizer.scale
                onUpdate(.init(
                    phase: .changed,
                    magnification: recognizer.scale,
                    startLocation: pinchStartLocation,
                    location: location
                ))
            case .ended, .cancelled, .failed:
                guard isPinching else { return }
                isPinching = false
                onUpdate(.init(
                    phase: .ended,
                    magnification: lastPinchMagnification,
                    startLocation: pinchStartLocation,
                    location: lastPinchLocation
                ))
                // 현재 남아 있는 손가락은 pan의 touchesBegan을 거치지 않았으므로
                // 완전히 떼었다가 새로 누른 터치부터 패닝을 시작한다.
                panRecognizer.isEnabled = true
            default:
                break
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let anchorView else { return }
            let location = recognizer.location(in: anchorView)
            switch recognizer.state {
            case .began:
                isPanning = true
                panStartLocation = location
                onUpdate(.init(
                    phase: .began,
                    magnification: 1,
                    startLocation: panStartLocation,
                    location: location
                ))
            case .changed:
                guard isPanning else { return }
                onUpdate(.init(
                    phase: .changed,
                    magnification: 1,
                    startLocation: panStartLocation,
                    location: location
                ))
            case .ended, .cancelled, .failed:
                guard isPanning else { return }
                isPanning = false
                onUpdate(.init(
                    phase: .ended,
                    magnification: 1,
                    startLocation: panStartLocation,
                    location: location
                ))
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if isViewportRecognizer(gestureRecognizer), isViewportRecognizer(otherGestureRecognizer) {
                return false
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let anchorView, anchorView.window != nil else { return false }
            return anchorView.bounds.contains(touch.location(in: anchorView))
        }

        private func isViewportRecognizer(_ recognizer: UIGestureRecognizer) -> Bool {
            recognizer === pinchRecognizer || recognizer === panRecognizer
        }
    }
}

#Preview("AAR 동선") {
    let store = InstructorPreviewFixture.store(floorPlan: InstructorFloorPlan(
        id: "preview-plan",
        name: "훈련장 A 도면",
        fileName: "훈련장 A 도면.png",
        referenceDistance: 15
    ), phase: .aar)

    return AARMovementView()
        .environment(store)
        .environment(AARStore())
        .frame(width: 1_008, height: 896)
        .preferredColorScheme(.dark)
}

#if DEBUG
@MainActor
private func unavailablePositionPreview() -> some View {
    let participants = Array(InstructorPreviewFixture.participants.prefix(3))
    let floorPlan = InstructorFloorPlan(
        id: "preview-unavailable-plan",
        name: "동선 실패 미리보기",
        fileName: "preview.png",
        referenceDistance: 15
    )
    let store = InstructorPreviewFixture.store(
        floorPlan: floorPlan,
        participants: participants,
        phase: .aar
    )
    let aarStore = AARStore()
    let delayedPath = AARTrackPath(vertices: [
        TrackResultVertex(
            t: 5,
            point: ImagePoint(x: 140, y: 180),
            part: 0,
            sampleIndex: 0
        ),
        TrackResultVertex(
            t: 10,
            point: ImagePoint(x: 280, y: 180),
            part: 0,
            sampleIndex: 1
        ),
    ])
    let trackedPath = AARTrackPath(vertices: [
        TrackResultVertex(
            t: 0,
            point: ImagePoint(x: 400, y: 220),
            part: 0,
            sampleIndex: 0
        ),
        TrackResultVertex(
            t: 10,
            point: ImagePoint(x: 500, y: 260),
            part: 0,
            sampleIndex: 1
        ),
    ])
    aarStore.configureMovementPreview(
        floorPlanImage: previewFloorPlanImage(),
        tracks: [
            participants[0].id: .ready(delayedPath, partial: false),
            participants[1].id: .unavailable("동선 보정 결과가 없습니다."),
            participants[2].id: .ready(trackedPath, partial: false),
        ],
        playbackPosition: 0
    )
    store.toggleParticipantSelection(participants[1].id)

    return AARMovementView()
        .environment(store)
        .environment(aarStore)
        .frame(width: 1_008, height: 896)
        .preferredColorScheme(.dark)
}

private func previewFloorPlanImage() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(
        size: CGSize(width: 600, height: 400),
        format: format
    ).image { context in
        UIColor.systemGray6.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        UIColor.systemGray3.setStroke()
        context.cgContext.setLineWidth(4)
        context.cgContext.stroke(CGRect(x: 40, y: 40, width: 520, height: 320))
        context.cgContext.move(to: CGPoint(x: 300, y: 40))
        context.cgContext.addLine(to: CGPoint(x: 300, y: 360))
        context.cgContext.strokePath()
    }
}

#Preview("AAR 동선 · 위치 확인 불가") {
    unavailablePositionPreview()
}
#endif
