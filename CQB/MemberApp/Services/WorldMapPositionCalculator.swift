import CoreGraphics
import CQBCore
import Foundation

nonisolated struct WorldMapPosition: Equatable, Sendable {
    let start: CGPoint
    let direction: CGPoint
}

nonisolated enum WorldMapPositionCalculator {
    static func position(pose: ARPose, alignment: WorldMapAlignment, map: TrainingMap) -> WorldMapPosition? {
        let values = [pose.x, pose.y, pose.z, pose.forwardX, pose.forwardZ,
                      alignment.rotationDegrees, alignment.pixelsPerMeter,
                      alignment.translation.x, alignment.translation.y]
        let length = hypot(pose.forwardX, pose.forwardZ)
        guard values.allSatisfy(\.isFinite), alignment.pixelsPerMeter > 0, length > 0.2 else { return nil }
        let p = alignment.imagePoint(x: pose.x, z: pose.z)
        let width = Double(map.manifest.imageWidth), height = Double(map.manifest.imageHeight)
        guard (0..<width).contains(p.x), (0..<height).contains(p.y),
              map.navigation.grid.isFree(MapPoint(x: p.x, y: p.y)) else { return nil }
        // 방향점은 방위 계산용이다. 가장자리에서도 방향을 보존하도록 도면 밖을 허용한다.
        let distance = max(1, 20 / alignment.pixelsPerMeter)
        let d = alignment.imagePoint(x: pose.x + distance * pose.forwardX / length,
                                     z: pose.z + distance * pose.forwardZ / length)
        guard d.x.isFinite, d.y.isFinite else { return nil }
        return WorldMapPosition(start: CGPoint(x: p.x / width, y: p.y / height),
                                direction: CGPoint(x: d.x / width, y: d.y / height))
    }
}
