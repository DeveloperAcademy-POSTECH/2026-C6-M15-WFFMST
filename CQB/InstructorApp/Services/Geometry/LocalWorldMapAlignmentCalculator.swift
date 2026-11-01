import CQBCore
import Foundation

nonisolated struct LocalWorldMapAlignmentResult: Equatable, Sendable {
    let alignment: WorldMapAlignment
    let scale: LocalPlanScale
}

/// AR 월드 좌표와 도면 대응점으로 유사 변환과 도면 축척을 함께 계산한다.
/// 첨부 PoC의 `PlanARTransform` 계산을 CQBCore 저장 계약에 맞게 옮긴 구현이다.
nonisolated enum LocalWorldMapAlignmentCalculator {
    static let algorithmVersion = "similarity-v1"

    static func calculate(
        correspondences: [WorldMapCorrespondence],
        imageWidth: Int,
        imageHeight: Int
    ) throws -> LocalWorldMapAlignmentResult {
        guard (1...4_096).contains(imageWidth), (1...4_096).contains(imageHeight) else {
            throw LocalFloorPlanError.invalid("도면 이미지의 가로와 세로는 1~4,096px이어야 합니다.")
        }
        guard (2...512).contains(correspondences.count) else {
            throw LocalFloorPlanError.invalid("공간 정렬에는 서로 다른 위치의 대응점이 2개 이상 필요합니다.")
        }
        guard correspondences.allSatisfy({ correspondence in
            let point = correspondence.planPoint
            let pose = correspondence.arPose
            return point.x.isFinite && point.y.isFinite
                && (0...1).contains(point.x) && (0...1).contains(point.y)
                && [pose.x, pose.y, pose.z, pose.forwardX, pose.forwardZ].allSatisfy(\.isFinite)
        }) else {
            throw LocalFloorPlanError.invalid("도면 대응점 또는 AR 위치 좌표가 유효하지 않습니다.")
        }

        let inputs = correspondences.map { (x: $0.arPose.x, z: $0.arPose.z) }
        let outputs = correspondences.map {
            (x: $0.planPoint.x * Double(imageWidth), y: $0.planPoint.y * Double(imageHeight))
        }
        let count = Double(correspondences.count)
        let meanX = inputs.reduce(0) { $0 + $1.x } / count
        let meanZ = inputs.reduce(0) { $0 + $1.z } / count
        let meanU = outputs.reduce(0) { $0 + $1.x } / count
        let meanV = outputs.reduce(0) { $0 + $1.y } / count

        var dot = 0.0
        var cross = 0.0
        var variance = 0.0
        for index in correspondences.indices {
            let x = inputs[index].x - meanX
            let z = inputs[index].z - meanZ
            let u = outputs[index].x - meanU
            let v = outputs[index].y - meanV
            dot += x * u + z * v
            cross += x * v - z * u
            variance += x * x + z * z
        }
        guard variance > 0.0001 else {
            throw LocalFloorPlanError.invalid("대응점은 실제 공간에서 15cm 이상 떨어진 위치에 지정해 주세요.")
        }

        let a = dot / variance
        let b = cross / variance
        let translationX = meanU - a * meanX + b * meanZ
        let translationY = meanV - b * meanX - a * meanZ
        let pixelsPerMeter = hypot(a, b)
        guard a.isFinite, b.isFinite, translationX.isFinite, translationY.isFinite,
              pixelsPerMeter.isFinite, pixelsPerMeter > 0 else {
            throw LocalFloorPlanError.invalid("대응점으로 도면 축척과 정렬을 계산할 수 없습니다.")
        }

        let squaredError = correspondences.indices.reduce(0.0) { sum, index in
            let mappedX = a * inputs[index].x - b * inputs[index].z + translationX
            let mappedY = b * inputs[index].x + a * inputs[index].z + translationY
            return sum + pow(mappedX - outputs[index].x, 2) + pow(mappedY - outputs[index].y, 2)
        }
        let rmsErrorMeters = sqrt(squaredError / count) / pixelsPerMeter

        guard let scale = farthestPairScale(
            correspondences: correspondences,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        ) else {
            throw LocalFloorPlanError.invalid("대응점은 실제 공간에서 15cm 이상 떨어진 위치에 지정해 주세요.")
        }
        _ = try LocalFloorPlanGeometry.validateScale(scale, width: imageWidth, height: imageHeight)

        return LocalWorldMapAlignmentResult(
            alignment: WorldMapAlignment(
                rotationDegrees: atan2(b, a) * 180 / .pi,
                pixelsPerMeter: pixelsPerMeter,
                translation: ImagePoint(x: translationX, y: translationY),
                rmsErrorMeters: rmsErrorMeters,
                algorithmVersion: algorithmVersion
            ),
            scale: scale
        )
    }

    private static func farthestPairScale(
        correspondences: [WorldMapCorrespondence],
        imageWidth: Int,
        imageHeight: Int
    ) -> LocalPlanScale? {
        var best: (first: Int, second: Int, meters: Double)?
        for first in correspondences.indices {
            for second in correspondences.indices.dropFirst(first + 1) {
                let lhs = correspondences[first].arPose
                let rhs = correspondences[second].arPose
                let meters = hypot(lhs.x - rhs.x, lhs.z - rhs.z)
                if meters > (best?.meters ?? 0) {
                    best = (first, second, meters)
                }
            }
        }
        guard let best, best.meters >= 0.15 else { return nil }
        let first = correspondences[best.first].planPoint
        let second = correspondences[best.second].planPoint
        let pixelDistance = hypot(
            (second.x - first.x) * Double(imageWidth),
            (second.y - first.y) * Double(imageHeight)
        )
        guard pixelDistance >= 10 else { return nil }
        return LocalPlanScale(
            a: LocalPlanPoint(x: first.x, y: first.y),
            b: LocalPlanPoint(x: second.x, y: second.y),
            meters: best.meters
        )
    }
}
