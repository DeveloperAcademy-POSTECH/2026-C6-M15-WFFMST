import CQBCore
import Foundation

@MainActor
protocol WorldMapScanning: AnyObject {
    var previewSession: AnyObject { get }
    var onFrameUpdate: ((LocalWorldMapFrameState) -> Void)? { get set }

    func start() async throws
    func captureCurrentPose() -> LocalWorldMapPoseCaptureResult
    func makeWorldMapArchive() async throws -> Data
    func stop()
}

