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

    func currentPose() throws -> ARPose {
        guard let transform = session.currentFrame?.camera.transform else {
            throw LocalARWorldMapScanError.poseUnavailable
        }
        let rawX = -Double(transform.columns.2.x)
        let rawZ = -Double(transform.columns.2.z)
        let length = hypot(rawX, rawZ)
        guard length > 0.0001 else { throw LocalARWorldMapScanError.poseUnavailable }
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
        let trackingMessage: String = switch frame.camera.trackingState {
        case .normal: "추적 정상"
        case .notAvailable: "카메라 추적을 시작할 수 없습니다"
        case .limited(.initializing): "주변을 천천히 비추며 초기화하세요"
        case .limited(.excessiveMotion): "iPad를 조금 더 천천히 움직이세요"
        case .limited(.insufficientFeatures): "특징이 많은 벽과 모서리를 비추세요"
        case .limited(.relocalizing): "저장된 공간을 다시 찾는 중입니다"
        case .limited: "카메라 추적이 제한되었습니다"
        }
        Task { @MainActor [weak self] in
            self?.onFrameUpdate?(LocalWorldMapFrameState(
                mapping: mapping,
                trackingMessage: trackingMessage
            ))
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

