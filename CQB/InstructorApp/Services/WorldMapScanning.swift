import CQBCore
import Foundation

@MainActor
protocol WorldMapScanning: AnyObject {
    var previewSession: AnyObject { get }
    var onFrameUpdate: ((LocalWorldMapFrameState) -> Void)? { get set }

    func start() async throws
    func currentPose() throws -> ARPose
    func makeWorldMapArchive() async throws -> Data
    func stop()
}

