import Foundation

/// 기록 시작 시 확정하며 저장된 원본/서버 계약에는 추가하지 않는다.
nonisolated enum RouteCorrectionMode: Equatable, Sendable {
    case manual
    case worldMap
}

/// 이동량은 회전 후 도면 축 기준 m다. y의 양수는 아래쪽이다.
nonisolated struct RouteRegistration: Hashable, Sendable {
    let offsetDegrees: Double
    var translationXMeters = 0.0
    var translationYMeters = 0.0
    var coherentOnly = false

    func anchor(from original: MapPoint, pixelsPerMeter: Double) -> MapPoint {
        MapPoint(x: original.x + translationXMeters * pixelsPerMeter,
                 y: original.y + translationYMeters * pixelsPerMeter)
    }

    var squaredTranslation: Double {
        translationXMeters * translationXMeters + translationYMeters * translationYMeters
    }

    static var worldMapCandidates: [Self] {
        let angles = stride(from: -30.0, through: 30.0, by: 5.0)
        let shifts: [(Double, Double)] = [
            (0, 0), (-0.5, 0), (0.5, 0), (-1, 0), (1, 0),
            (0, -0.5), (0, 0.5), (0, -1), (0, 1)
        ]
        return angles.flatMap { angle in
            shifts.map { x, y in
                Self(offsetDegrees: angle, translationXMeters: x, translationYMeters: y, coherentOnly: true)
            }
        }
    }

    func isNear(_ other: Self) -> Bool {
        abs(offsetDegrees - other.offsetDegrees) < 6
            && hypot(translationXMeters - other.translationXMeters,
                     translationYMeters - other.translationYMeters) < 0.5
    }
}
