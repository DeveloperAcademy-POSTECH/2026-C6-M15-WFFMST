import ARKit
import AVFoundation
import Observation
import UIKit

/// 카메라의 단일 소유자. 같은 ARFrame 시계를 영상 PTS와 동선 t에 사용한다.
@MainActor @Observable
final class ARRecordingService: NSObject, @preconcurrency ARSessionDelegate {
    let session = ARSession()
    private(set) var isReady = false
    private(set) var statusMessage = "카메라 준비 중"
    /// 시작 전 방향 안정화와 별개인, 현재 AR 추적 품질 안내.
    private(set) var trackingWarning: String?
    private(set) var fatalError: String?
    private(set) var isRecording = false
    private(set) var samples: [RawTrackSample] = []
    private(set) var rotationDegrees = 0.0
    @ObservationIgnored private let writer = ARFrameVideoWriter()
    @ObservationIgnored private var origin = SIMD3<Float>(repeating: 0)
    @ObservationIgnored private var firstTimestamp = 0.0
    @ObservationIgnored private var lastSampleTime = -Double.infinity
    @ObservationIgnored private var normalSince: Double?
    @ObservationIgnored private var headings: [(Double, Double)] = []
    @ObservationIgnored private var segment = 0
    @ObservationIgnored private var wasNormal = false
    @ObservationIgnored private var running = false
    @ObservationIgnored private var startingSession = false
    @ObservationIgnored private var wantsRunning = false

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    func start() async {
        wantsRunning = true
        guard !running, !startingSession else { return }
        startingSession = true
        defer { startingSession = false }
        guard ARWorldTrackingConfiguration.isSupported else {
            statusMessage = "이 기기는 AR 동선 추적을 지원하지 않습니다."
            return
        }
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard wantsRunning else { return }
        guard allowed else {
            statusMessage = "설정에서 카메라 접근을 허용해주세요."
            return
        }
        fatalError = nil
        trackingWarning = nil
        normalSince = nil
        headings = []
        isReady = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        // 영상과 추적 모두 이 세션만 사용한다. 재시작 시 이전 좌표계를 재사용하지 않는다.
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        running = true
    }

    func stop() {
        guard !isRecording else { return }
        wantsRunning = false
        session.pause()
        running = false
        trackingWarning = nil
        isReady = false
        normalSince = nil
        headings = []
    }

    func discardFinishedCapture() {
        guard !isRecording else { return }
        samples = []
    }

    func startRecording(to url: URL, start: MapPoint, direction: MapPoint) throws {
        guard !isRecording, isReady, let frame = session.currentFrame,
              case .normal = frame.camera.trackingState,
              let heading = RouteHeading.stableCameraDirection(headings.map(\.1)),
              let rotation = RouteHeading.rotation(start: start, toward: direction, referenceRadians: heading) else {
            throw CaptureError.notReady
        }
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation ?? .landscapeRight
        try writer.start(firstFrame: frame.capturedImage, timestamp: frame.timestamp,
                         outputURL: url, orientation: orientation)
        let position = frame.camera.transform.columns.3
        origin = SIMD3(position.x, position.y, position.z)
        firstTimestamp = frame.timestamp
        lastSampleTime = -Double.infinity
        segment = 0
        wasNormal = true
        samples = []
        rotationDegrees = rotation
        isRecording = true
        isReady = false
        trackingWarning = nil
        statusMessage = "영상·동선 기록 중"
        recordSample(frame)
    }

    func stopRecording() async throws -> URL {
        guard isRecording else { throw CaptureError.notRecording }
        if let frame = session.currentFrame, frame.timestamp > firstTimestamp + lastSampleTime {
            recordSample(frame, force: true)
        }
        isRecording = false
        return try await withCheckedThrowingContinuation { continuation in
            writer.finish { continuation.resume(with: $0) }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let normal: Bool
        switch frame.camera.trackingState {
        case .normal:
            normal = true
            statusMessage = isRecording ? "영상·동선 기록 중" : "선택한 방향을 바라보고 잠시 정지해주세요."
        case .limited(let reason):
            normal = false
            switch reason {
            case .initializing: statusMessage = "주변 공간을 인식하고 있습니다."
            case .excessiveMotion: statusMessage = "카메라를 천천히 움직여주세요."
            case .insufficientFeatures: statusMessage = "주변 사물이 보이도록 카메라를 향해주세요."
            case .relocalizing: statusMessage = "위치를 다시 찾고 있습니다."
            @unknown default: statusMessage = "동선 추적이 불안정합니다."
            }
        case .notAvailable: normal = false; statusMessage = "동선 추적을 사용할 수 없습니다."
        }
        trackingWarning = normal ? nil : statusMessage
        // 방향 안정화는 녹화 시작을 위한 조건이다. 녹화 중 회전·이동은 정상 동작이다.
        if normal && !isRecording {
            if normalSince == nil { normalSince = frame.timestamp }
            let forward = -frame.camera.transform.columns.2
            if hypot(forward.x, forward.z) > 0.2 {
                headings.append((frame.timestamp, atan2(Double(forward.z), Double(forward.x))))
            } else { headings = [] }
            headings.removeAll { frame.timestamp - $0.0 > 0.5 }
            isReady = frame.timestamp - (normalSince ?? frame.timestamp) >= 1
                && RouteHeading.stableCameraDirection(headings.map(\.1)) != nil
            if isReady { statusMessage = "녹화·동선 추적 준비 완료" }
        } else {
            normalSince = nil
            headings = []
            isReady = false
        }
        guard isRecording else { return }
        if let failure = writer.failureDescription {
            fatalError = failure
            return
        }
        writer.append(pixelBuffer: frame.capturedImage, timestamp: frame.timestamp)
        // 상태 변화는 10Hz 제한과 무관하게 남겨 짧은 단절도 보존한다.
        recordSample(frame, force: normal != wasNormal)
    }

    private func recordSample(_ frame: ARFrame, force: Bool = false) {
        let t = frame.timestamp - firstTimestamp
        if t - lastSampleTime > 0.5, let last = samples.last, wasNormal {
            samples.append(RawTrackSample(t: last.t + 0.000001, x: last.x, y: last.y, z: last.z,
                relative: nil, trackingState: "frameGap", segment: segment))
            wasNormal = false
        }
        guard t >= 0, t > lastSampleTime, force || t - lastSampleTime >= 0.1 else { return }
        let normal: Bool
        let state: String
        switch frame.camera.trackingState {
        case .normal: normal = true; state = "normal"
        case .notAvailable: normal = false; state = "notAvailable"
        case .limited(let reason): normal = false; state = "limited:\(reason)"
        }
        if normal && !wasNormal { segment += 1 }
        wasNormal = normal
        let p = frame.camera.transform.columns.3
        samples.append(RawTrackSample(t: t, x: Double(p.x), y: Double(p.y), z: Double(p.z),
            relative: normal ? MapPoint(x: Double(p.x - origin.x), y: Double(p.z - origin.z)) : nil,
            trackingState: state, segment: segment))
        lastSampleTime = t
    }

    func sessionWasInterrupted(_ session: ARSession) {
        markInterruption("interrupted")
        fatalError = "카메라 사용이 중단되어 녹화를 종료합니다."
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        markInterruption("sessionFailed")
        fatalError = error.localizedDescription
    }

    private func markInterruption(_ state: String) {
        isReady = false
        normalSince = nil
        headings = []
        guard isRecording, let last = samples.last else { return }
        samples.append(RawTrackSample(t: last.t + 0.000001, x: last.x, y: last.y, z: last.z,
            relative: nil, trackingState: state, segment: segment))
        lastSampleTime = last.t + 0.000001
        wasNormal = false
    }

    private enum CaptureError: LocalizedError {
        case notReady, notRecording
        var errorDescription: String? {
            switch self {
            case .notReady: "선택한 방향을 바라보고 카메라가 안정될 때까지 기다려주세요."
            case .notRecording: "종료할 녹화가 없습니다."
            }
        }
    }
}
