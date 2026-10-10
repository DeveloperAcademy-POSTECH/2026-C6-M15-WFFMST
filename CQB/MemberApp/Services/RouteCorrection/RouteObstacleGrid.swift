import Foundation

nonisolated struct MapPoint: Codable, Sendable { var x: Double; var y: Double }

/// Pixel coordinates, independent of UIKit so geometry can be tested on the Mac.
nonisolated struct RouteObstacleGrid: Sendable {
    let columns: Int
    let rows: Int
    let cellSize: Double
    let blocked: [UInt8]
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int

    nonisolated func isFree(_ p: MapPoint) -> Bool {
        guard p.x.isFinite, p.y.isFinite, cellSize > 0,
              p.x >= 0, p.y >= 0, p.x < Double(columns)*cellSize, p.y < Double(rows)*cellSize else { return false }
        let x = Int(floor(p.x / cellSize)), y = Int(floor(p.y / cellSize))
        guard x >= max(0, minX), x <= min(columns - 1, maxX),
              y >= max(0, minY), y <= min(rows - 1, maxY) else { return false }
        return blocked[y * columns + x] == 0
    }

    /// Supercover traversal: also checks both adjacent cells at a grid corner.
    nonisolated func canTravel(_ a: MapPoint, _ b: MapPoint) -> Bool {
        guard isFree(a), isFree(b) else { return false }
        let ax = a.x / cellSize, ay = a.y / cellSize
        let bx = b.x / cellSize, by = b.y / cellSize
        var x = Int(floor(ax)), y = Int(floor(ay))
        let endX = Int(floor(bx)), endY = Int(floor(by))
        let dx = bx - ax, dy = by - ay
        let sx = dx >= 0 ? 1 : -1, sy = dy >= 0 ? 1 : -1
        let deltaX = dx == 0 ? Double.infinity : abs(1 / dx)
        let deltaY = dy == 0 ? Double.infinity : abs(1 / dy)
        var nextX = dx == 0 ? Double.infinity : (dx > 0 ? Double(x + 1) - ax : ax - Double(x)) / abs(dx)
        var nextY = dy == 0 ? Double.infinity : (dy > 0 ? Double(y + 1) - ay : ay - Double(y)) / abs(dy)
        func freeCell(_ cx: Int, _ cy: Int) -> Bool {
            cx >= max(0, minX) && cx <= min(columns - 1, maxX) &&
            cy >= max(0, minY) && cy <= min(rows - 1, maxY) && blocked[cy * columns + cx] == 0
        }
        while x != endX || y != endY {
            if abs(nextX - nextY) < 1e-10 {
                guard freeCell(x + sx, y), freeCell(x, y + sy) else { return false }
                x += sx; y += sy; nextX += deltaX; nextY += deltaY
            } else if nextX < nextY {
                x += sx; nextX += deltaX
            } else {
                y += sy; nextY += deltaY
            }
            guard freeCell(x, y) else { return false }
        }
        return true
    }
}

