import Foundation

/// App-local replay of the PoC's rasterization-v2 policy. Preview and registration
/// deliberately call the same resolver; the base grid is never mutated.
enum LocalFloorPlanGeometry {
    nonisolated static func validateScale(_ scale: LocalPlanScale, width: Int, height: Int) throws -> Double {
        try validateImageSize(width: width, height: height)
        guard scale.a.isValid, scale.b.isValid, scale.meters.isFinite,
              scale.meters > 0, scale.meters <= 1_000 else {
            throw LocalFloorPlanError.invalid("기준점은 도면 안에, 실제 거리는 0m 초과 1,000m 이하로 입력해 주세요.")
        }
        let pixels = hypot((scale.b.x - scale.a.x) * Double(width),
                           (scale.b.y - scale.a.y) * Double(height))
        guard pixels >= 10 else {
            throw LocalFloorPlanError.invalid("축척 기준점은 이미지에서 10px 이상 떨어져야 합니다.")
        }
        let result = pixels / scale.meters
        guard result.isFinite else { throw LocalFloorPlanError.invalid("축척을 계산할 수 없는 거리입니다.") }
        return result
    }

    nonisolated static func validateOutline(_ points: [LocalPlanPoint]) throws {
        guard (3...512).contains(points.count), points.allSatisfy(\.isValid) else {
            throw LocalFloorPlanError.invalid("실내 외곽은 도면 안의 점 3~512개로 지정해 주세요.")
        }
        var twiceArea = 0.0
        for index in points.indices {
            try Task.checkCancellation()
            let next = (index + 1) % points.count
            let a = points[index], b = points[next]
            guard hypot(a.x - b.x, a.y - b.y) > 1e-9 else {
                throw LocalFloorPlanError.invalid("외곽에 같은 점을 연속해서 지정할 수 없습니다.")
            }
            // Adjacent edges may share only their endpoint, not overlap backwards.
            let c = points[(index + 2) % points.count]
            if abs(cross(a, b, c)) <= 1e-12,
               (a.x - b.x) * (c.x - b.x) + (a.y - b.y) * (c.y - b.y) > 0 {
                throw LocalFloorPlanError.invalid("외곽 선분이 겹치지 않게 지정해 주세요.")
            }
            twiceArea += a.x * b.y - b.x * a.y
            for other in (index + 1)..<points.count {
                let otherNext = (other + 1) % points.count
                if next == other || otherNext == index { continue }
                if intersects(a, b, points[other], points[otherNext]) {
                    throw LocalFloorPlanError.invalid("외곽 선분이 서로 교차하지 않게 지정해 주세요.")
                }
            }
        }
        guard abs(twiceArea) > 1e-12 else {
            throw LocalFloorPlanError.invalid("외곽은 면적이 있는 닫힌 영역이어야 합니다.")
        }
    }

    nonisolated static func resolve(
        base: LocalObstacleGrid, width: Int, height: Int,
        strokes: [LocalEditStroke], outline: [LocalPlanPoint]
    ) throws -> LocalObstacleGrid {
        try validateImageSize(width: width, height: height)
        try validateGrid(base)
        guard base.columns == (width + base.cellSizePixels - 1) / base.cellSizePixels,
              base.rows == (height + base.cellSizePixels - 1) / base.cellSizePixels,
              strokes.count <= 20_000 else {
            throw LocalFloorPlanError.invalid("도면과 장애물 격자의 크기가 맞지 않거나 편집 횟수가 너무 많습니다.")
        }
        if !outline.isEmpty { try validateOutline(outline) }
        var pointCount = 0
        for stroke in strokes {
            try Task.checkCancellation()
            guard !stroke.points.isEmpty, stroke.points.count <= 250_000 - pointCount,
                  stroke.normalizedDiameter.isFinite, stroke.normalizedDiameter > 0,
                  stroke.normalizedDiameter <= 0.1, stroke.points.allSatisfy(\.isValid) else {
                throw LocalFloorPlanError.invalid("편집 획의 좌표·굵기 또는 최대 입력량을 확인해 주세요.")
            }
            pointCount += stroke.points.count
        }
        var result = base
        let cellSize = Double(base.cellSizePixels)
        let extent = (Double(width) / cellSize, Double(height) / cellSize)
        for stroke in strokes {
            try Task.checkCancellation()
            let radius = max(0.5, stroke.normalizedDiameter * Double(min(width, height)) / cellSize / 2)
            let value: UInt8 = stroke.mode == .block ? 1 : 0
            try paint(stroke.points, radius: radius, value: value, extent: extent, grid: &result)
        }
        // The ceil-sized last row/column can have a center beyond the image.
        // Always block these cells, including when no outline is supplied for preview.
        for y in 0..<base.rows {
            try Task.checkCancellation()
            for x in 0..<base.columns {
                let point = LocalPlanPoint(x: (Double(x) + 0.5) / extent.0,
                                           y: (Double(y) + 0.5) / extent.1)
                if point.x >= 1 || point.y >= 1 || (!outline.isEmpty && !contains(point, polygon: outline)) {
                    result.blocked[y * base.columns + x] = 1
                }
            }
        }
        return result
    }

    nonisolated static func validateGrid(_ grid: LocalObstacleGrid) throws {
        guard (1...4_096).contains(grid.columns), (1...4_096).contains(grid.rows),
              (1...4_096).contains(grid.cellSizePixels),
              grid.blocked.count == grid.columns * grid.rows,
              grid.blocked.allSatisfy({ $0 <= 1 }) else {
            throw LocalFloorPlanError.invalid("유효하지 않은 장애물 격자입니다.")
        }
    }

    nonisolated private static func validateImageSize(width: Int, height: Int) throws {
        guard (1...4_096).contains(width), (1...4_096).contains(height) else {
            throw LocalFloorPlanError.invalid("도면 이미지의 가로와 세로는 1~4,096px이어야 합니다.")
        }
    }

    nonisolated private static func cross(_ a: LocalPlanPoint, _ b: LocalPlanPoint, _ c: LocalPlanPoint) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    nonisolated private static func onSegment(_ p: LocalPlanPoint, _ a: LocalPlanPoint, _ b: LocalPlanPoint) -> Bool {
        abs(cross(a, b, p)) <= 1e-12 && p.x >= min(a.x, b.x) - 1e-12 && p.x <= max(a.x, b.x) + 1e-12
            && p.y >= min(a.y, b.y) - 1e-12 && p.y <= max(a.y, b.y) + 1e-12
    }

    nonisolated private static func intersects(_ a: LocalPlanPoint, _ b: LocalPlanPoint,
                                               _ c: LocalPlanPoint, _ d: LocalPlanPoint) -> Bool {
        let abC = cross(a, b, c), abD = cross(a, b, d)
        let cdA = cross(c, d, a), cdB = cross(c, d, b)
        if ((abC > 0 && abD < 0) || (abC < 0 && abD > 0)) &&
            ((cdA > 0 && cdB < 0) || (cdA < 0 && cdB > 0)) { return true }
        return onSegment(c, a, b) || onSegment(d, a, b) || onSegment(a, c, d) || onSegment(b, c, d)
    }

    nonisolated private static func contains(_ point: LocalPlanPoint, polygon: [LocalPlanPoint]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for index in polygon.indices {
            let a = polygon[index], b = polygon[previous]
            if onSegment(point, a, b) { return true }
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            previous = index
        }
        return inside
    }

    nonisolated private static func paint(_ points: [LocalPlanPoint], radius: Double, value: UInt8,
                                          extent: (Double, Double), grid: inout LocalObstacleGrid) throws {
        func position(_ point: LocalPlanPoint) -> (x: Double, y: Double) {
            (min(point.x * extent.0, Double(grid.columns - 1)),
             min(point.y * extent.1, Double(grid.rows - 1)))
        }
        guard let first = points.first else { return }
        var previous = position(first)
        try paintDisk(at: previous, radius: radius, value: value, grid: &grid)
        for point in points.dropFirst() {
            try Task.checkCancellation()
            let current = position(point)
            let steps = max(1, Int(ceil(hypot(current.x - previous.x, current.y - previous.y) * 2)))
            for step in 0...steps {
                if step % 64 == 0 { try Task.checkCancellation() }
                let t = Double(step) / Double(steps)
                try paintDisk(at: (previous.x + (current.x - previous.x) * t,
                                   previous.y + (current.y - previous.y) * t),
                              radius: radius, value: value, grid: &grid)
            }
            previous = current
        }
    }

    nonisolated private static func paintDisk(at center: (x: Double, y: Double), radius: Double,
                                              value: UInt8, grid: inout LocalObstacleGrid) throws {
        let minX = max(0, Int(floor(center.x - radius)))
        let maxX = min(grid.columns - 1, Int(ceil(center.x + radius)))
        let minY = max(0, Int(floor(center.y - radius)))
        let maxY = min(grid.rows - 1, Int(ceil(center.y + radius)))
        var touched = false
        for y in minY...maxY {
            if y % 64 == 0 { try Task.checkCancellation() }
            for x in minX...maxX {
                let dx = Double(x) - center.x, dy = Double(y) - center.y
                if dx * dx + dy * dy <= radius * radius {
                    grid.blocked[y * grid.columns + x] = value
                    touched = true
                }
            }
        }
        // PoC rasterization v2: guarantee coverage for a sub-cell tap/diagonal.
        if !touched {
            let x = min(grid.columns - 1, max(0, Int(center.x.rounded())))
            let y = min(grid.rows - 1, max(0, Int(center.y.rounded())))
            grid.blocked[y * grid.columns + x] = value
        }
    }
}
