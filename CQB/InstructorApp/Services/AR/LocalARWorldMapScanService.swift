import ARKit
import AVFoundation
import CQBCore
import Foundation

@MainActor
final class LocalARWorldMapScanService: NSObject, WorldMapScanning, ARSessionDelegate {
    private let session = ARSession()
    var onFrameUpdate: ((LocalWorldMapFrameState) -> Void)?
    var previewSession: AnyObject { session }

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    func start() async throws {
        let authorized = await AVCaptureDevice.requestAccess(for: .video)
        guard authorized else { throw LocalARWorldMapScanError.cameraPermissionDenied }
        guard ARWorldTrackingConfiguration.isSupported else {
            throw LocalARWorldMapScanError.worldTrackingUnavailable
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func captureCurrentPose() -> LocalWorldMapPoseCaptureResult {
        guard let frame = session.currentFrame else {
            return .failed(LocalARWorldMapScanError.poseUnavailable.localizedDescription)
        }
        let tracking = Self.trackingState(for: frame.camera.trackingState)
        guard tracking.canCapture else { return .trackingUnavailable(tracking) }
        guard let pose = Self.pose(from: frame.camera.transform) else {
            return .failed(LocalARWorldMapScanError.poseUnavailable.localizedDescription)
        }
        return .captured(pose)
    }

    private static func pose(from transform: simd_float4x4) -> ARPose? {
        let rawX = -Double(transform.columns.2.x)
        let rawZ = -Double(transform.columns.2.z)
        let length = hypot(rawX, rawZ)
        guard length > 0.0001 else { return nil }
        return ARPose(
            x: Double(transform.columns.3.x),
            y: Double(transform.columns.3.y),
            z: Double(transform.columns.3.z),
            forwardX: rawX / length,
            forwardZ: rawZ / length
        )
    }

    func makeWorldMapArchive() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            session.getCurrentWorldMap { worldMap, error in
                if let error { continuation.resume(throwing: error) }
                else if let worldMap {
                    do {
                        continuation.resume(returning: try NSKeyedArchiver.archivedData(
                            withRootObject: worldMap,
                            requiringSecureCoding: true
                        ))
                    } catch { continuation.resume(throwing: error) }
                } else {
                    continuation.resume(throwing: LocalARWorldMapScanError.worldMapUnavailable)
                }
            }
        }
    }

    func stop() { session.pause() }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let mapping: LocalWorldMapMappingState = switch frame.worldMappingStatus {
        case .notAvailable: .unavailable
        case .limited: .limited
        case .extending: .extending
        case .mapped: .mapped
        @unknown default: .unavailable
        }
        let tracking = Self.trackingState(for: frame.camera.trackingState)
        Task { @MainActor [weak self] in
            self?.onFrameUpdate?(LocalWorldMapFrameState(
                mapping: mapping,
                tracking: tracking
            ))
        }
    }

    private nonisolated static func trackingState(
        for state: ARCamera.TrackingState
    ) -> LocalWorldMapTrackingState {
        switch state {
        case .normal: .normal
        case .notAvailable: .notAvailable
        case .limited(.initializing): .initializing
        case .limited(.excessiveMotion): .excessiveMotion
        case .limited(.insufficientFeatures): .insufficientFeatures
        case .limited(.relocalizing): .relocalizing
        case .limited: .limited
        }
    }
}

private enum LocalARWorldMapScanError: LocalizedError {
    case cameraPermissionDenied, worldTrackingUnavailable, poseUnavailable, worldMapUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied: "AR 스캔을 위해 카메라 권한이 필요합니다."
        case .worldTrackingUnavailable: "이 기기에서는 AR 공간 스캔을 사용할 수 없습니다."
        case .poseUnavailable: "현재 위치를 읽을 수 없습니다. 잠시 후 다시 시도해주세요."
        case .worldMapUnavailable: "WorldMap을 생성하지 못했습니다."
        }
    }
}

