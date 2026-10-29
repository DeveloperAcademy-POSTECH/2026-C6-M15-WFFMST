import Foundation

/// 벽 격자와 원본의 무채색 선을 이용해 이동 가능 영역의 경계를 제안합니다.
/// 원본 선은 외곽 추론에만 사용하며 최종 장애물 마스크에는 추가하지 않습니다.
enum LocalBlockedRegionAutoFill {
    private static let maximumWorkingDimension = 512
    private static let candidateRadii = [0, 1, 2, 3, 4, 6, 8, 12]

    nonisolated static func suggest(
        base: LocalObstacleGrid,
        rgba: [UInt8],
        width: Int,
        height: Int
    ) throws -> LocalBlockedRegionSuggestion? {
        try LocalFloorPlanGeometry.validateGrid(base)
        guard width > 0, height > 0, width <= 4_096, height <= 4_096,
              rgba.count == width * height * 4,
              base.columns == (width + base.cellSizePixels - 1) / base.cellSizePixels,
              base.rows == (height + base.cellSizePixels - 1) / base.cellSizePixels else {
            throw LocalFloorPlanError.invalid("자동 이동 불가 영역 입력의 크기가 올바르지 않습니다.")
        }

        let reduction = max(1, Int(ceil(
            Double(max(base.columns, base.rows)) / Double(maximumWorkingDimension)
        )))
        let columns = (base.columns + reduction - 1) / reduction
        let rows = (base.rows + reduction - 1) / reduction
        var wall = [UInt8](repeating: 0, count: columns * rows)
        for row in 0..<base.rows {
            if row % 64 == 0 { try Task.checkCancellation() }
            for column in 0..<base.columns where base.blocked[row * base.columns + column] == 1 {
                wall[(row / reduction) * columns + column / reduction] = 1
            }
        }

        var sourceLine = [UInt8](repeating: 0, count: columns * rows)
        let pixelsPerWorkingCell = base.cellSizePixels * reduction
        for y in 0..<height {
            if y % 64 == 0 { try Task.checkCancellation() }
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let red = Int(rgba[offset])
                let green = Int(rgba[offset + 1])
                let blue = Int(rgba[offset + 2])
                let gray = (red * 77 + green * 150 + blue * 29) >> 8
                if gray < 237, max(red, green, blue) - min(red, green, blue) < 70 {
                    let column = min(columns - 1, x / pixelsPerWorkingCell)
                    let row = min(rows - 1, y / pixelsPerWorkingCell)
                    sourceLine[row * columns + column] = 1
                }
            }
        }

        let evidence = zip(wall, sourceLine).map { $0 == 1 || $1 == 1 ? UInt8(1) : UInt8(0) }
        let evidenceCount = evidence.reduce(0) { $0 + Int($1) }
        guard evidenceCount > 0 else { return nil }

        var best: Candidate?
        for radius in candidateRadii {
            try Task.checkCancellation()
            let sealed = try closing(evidence, columns: columns, rows: rows, radius: radius)
            let outside = try borderFlood(blocked: sealed, columns: columns, rows: rows)
            let enclosed = outside.map { $0 == 0 ? UInt8(1) : UInt8(0) }
            let component = try largestComponent(enclosed, columns: columns, rows: rows)
            let area = component.reduce(0) { $0 + Int($1) }
            guard area > 0 else { continue }
            let areaRatio = Double(area) / Double(columns * rows)
            let coveredEvidence = zip(evidence, component).reduce(0) {
                $0 + ($1.0 == 1 && $1.1 == 1 ? 1 : 0)
            }
            let coverage = Double(coveredEvidence) / Double(evidenceCount)
            let enclosureGain = Double(area) / Double(evidenceCount)
            let plausible = (0.05...0.80).contains(areaRatio) && enclosureGain >= 2
            var score = coverage + min(enclosureGain / 8, 1) - Double(radius) * 0.004
            if !plausible { score -= 1.25 }
            let candidate = Candidate(
                component: component,
                radius: radius,
                areaRatio: areaRatio,
                coverage: coverage,
                enclosureGain: enclosureGain,
                score: score,
                plausible: plausible
            )
            if best == nil || candidate.score > best!.score { best = candidate }
        }

        guard let best, best.plausible, best.coverage >= 0.70,
              let rawOutline = try traceOuterBoundary(
                best.component,
                columns: columns,
                rows: rows
              ) else { return nil }
        let outline = simplified(rawOutline, maximumCount: 128)
        guard outline.count >= 3 else { return nil }
        do { try LocalFloorPlanGeometry.validateOutline(outline) }
        catch { return nil }

        let confidence = min(1, max(0, (best.score - 0.9) / 1.1))
        guard confidence >= 0.45 else { return nil }
        return LocalBlockedRegionSuggestion(
            outline: outline,
            confidence: confidence,
            closingRadiusCells: best.radius * reduction
        )
    }

    private struct Candidate {
        let component: [UInt8]
        let radius: Int
        let areaRatio: Double
        let coverage: Double
        let enclosureGain: Double
        let score: Double
        let plausible: Bool
    }

    private nonisolated static func closing(
        _ input: [UInt8], columns: Int, rows: Int, radius: Int
    ) throws -> [UInt8] {
        guard radius > 0 else { return input }
        let dilated = try windowFilter(
            input, columns: columns, rows: rows, radius: radius, requiresFullWindow: false
        )
        return try windowFilter(
            dilated, columns: columns, rows: rows, radius: radius, requiresFullWindow: true
        )
    }

    /// 적분 영상으로 정사각 dilation/erosion을 각각 O(width×height)에 계산합니다.
    private nonisolated static func windowFilter(
        _ input: [UInt8], columns: Int, rows: Int, radius: Int, requiresFullWindow: Bool
    ) throws -> [UInt8] {
        let prefixColumns = columns + 1
        var prefix = [Int](repeating: 0, count: prefixColumns * (rows + 1))
        for y in 0..<rows {
            if y % 64 == 0 { try Task.checkCancellation() }
            var rowSum = 0
            for x in 0..<columns {
                rowSum += Int(input[y * columns + x])
                prefix[(y + 1) * prefixColumns + x + 1] = prefix[y * prefixColumns + x + 1] + rowSum
            }
        }
        let fullArea = (radius * 2 + 1) * (radius * 2 + 1)
        var output = [UInt8](repeating: 0, count: input.count)
        for y in 0..<rows {
            if y % 64 == 0 { try Task.checkCancellation() }
            let minimumY = max(0, y - radius)
            let maximumY = min(rows - 1, y + radius)
            for x in 0..<columns {
                let minimumX = max(0, x - radius)
                let maximumX = min(columns - 1, x + radius)
                let sum = prefix[(maximumY + 1) * prefixColumns + maximumX + 1]
                    - prefix[minimumY * prefixColumns + maximumX + 1]
                    - prefix[(maximumY + 1) * prefixColumns + minimumX]
                    + prefix[minimumY * prefixColumns + minimumX]
                output[y * columns + x] = requiresFullWindow
                    ? (sum == fullArea ? 1 : 0)
                    : (sum > 0 ? 1 : 0)
            }
        }
        return output
    }

    private nonisolated static func borderFlood(
        blocked: [UInt8], columns: Int, rows: Int
    ) throws -> [UInt8] {
        var outside = [UInt8](repeating: 0, count: blocked.count)
        var queue = [Int]()
        queue.reserveCapacity(blocked.count)
        func append(_ index: Int) {
            if blocked[index] == 0, outside[index] == 0 {
                outside[index] = 1
                queue.append(index)
            }
        }
        for x in 0..<columns {
            append(x)
            append((rows - 1) * columns + x)
        }
        for y in 0..<rows {
            append(y * columns)
            append(y * columns + columns - 1)
        }
        var cursor = 0
        while cursor < queue.count {
            if cursor % 16_384 == 0 { try Task.checkCancellation() }
            let index = queue[cursor]
            cursor += 1
            let x = index % columns
            let y = index / columns
            if x > 0 { append(index - 1) }
            if x + 1 < columns { append(index + 1) }
            if y > 0 { append(index - columns) }
            if y + 1 < rows { append(index + columns) }
        }
        return outside
    }

    private nonisolated static func largestComponent(
        _ input: [UInt8], columns: Int, rows: Int
    ) throws -> [UInt8] {
        var visited = [UInt8](repeating: 0, count: input.count)
        var best = [Int]()
        for start in input.indices where input[start] == 1 && visited[start] == 0 {
            try Task.checkCancellation()
            var component = [start]
            visited[start] = 1
            var cursor = 0
            while cursor < component.count {
                let index = component[cursor]
                cursor += 1
                let x = index % columns
                let y = index / columns
                for neighbor in [
                    x > 0 ? index - 1 : -1,
                    x + 1 < columns ? index + 1 : -1,
                    y > 0 ? index - columns : -1,
                    y + 1 < rows ? index + columns : -1
                ] where neighbor >= 0 && input[neighbor] == 1 && visited[neighbor] == 0 {
                    visited[neighbor] = 1
                    component.append(neighbor)
                }
            }
            if component.count > best.count { best = component }
        }
        var output = [UInt8](repeating: 0, count: input.count)
        for index in best { output[index] = 1 }
        return output
    }

    private struct Edge: Hashable {
        let start: Int
        let end: Int
    }

    private nonisolated static func traceOuterBoundary(
        _ component: [UInt8], columns: Int, rows: Int
    ) throws -> [LocalPlanPoint]? {
        let vertexColumns = columns + 1
        func vertex(_ x: Int, _ y: Int) -> Int { y * vertexColumns + x }
        var edges = Set<Edge>()
        for y in 0..<rows {
            if y % 64 == 0 { try Task.checkCancellation() }
            for x in 0..<columns where component[y * columns + x] == 1 {
                if y == 0 || component[(y - 1) * columns + x] == 0 {
                    edges.insert(Edge(start: vertex(x, y), end: vertex(x + 1, y)))
                }
                if x + 1 == columns || component[y * columns + x + 1] == 0 {
                    edges.insert(Edge(start: vertex(x + 1, y), end: vertex(x + 1, y + 1)))
                }
                if y + 1 == rows || component[(y + 1) * columns + x] == 0 {
                    edges.insert(Edge(start: vertex(x + 1, y + 1), end: vertex(x, y + 1)))
                }
                if x == 0 || component[y * columns + x - 1] == 0 {
                    edges.insert(Edge(start: vertex(x, y + 1), end: vertex(x, y)))
                }
            }
        }
        var outgoing = [Int: [Int]]()
        for edge in edges { outgoing[edge.start, default: []].append(edge.end) }
        var unused = edges
        var bestLoop = [Int]()
        while let first = unused.first {
            var loop = [first.start]
            var current = first
            unused.remove(first)
            while current.end != first.start, loop.count <= edges.count {
                loop.append(current.end)
                guard let nextEnd = outgoing[current.end]?.first(where: {
                    unused.contains(Edge(start: current.end, end: $0))
                }) else { break }
                current = Edge(start: current.end, end: nextEnd)
                unused.remove(current)
            }
            if current.end == first.start, loop.count > bestLoop.count { bestLoop = loop }
        }
        guard bestLoop.count >= 3 else { return nil }
        return bestLoop.map { value in
            let x = value % vertexColumns
            let y = value / vertexColumns
            return LocalPlanPoint(
                x: min(1, max(0, Double(x) / Double(columns))),
                y: min(1, max(0, Double(y) / Double(rows)))
            )
        }
    }

    private nonisolated static func simplified(
        _ points: [LocalPlanPoint], maximumCount: Int
    ) -> [LocalPlanPoint] {
        guard points.count > maximumCount else { return removingCollinear(points) }
        var tolerance = 1.0 / 512.0
        var result = points
        while result.count > maximumCount, tolerance <= 0.05 {
            let split = farthestIndex(from: points[0], in: points)
            let first = rdp(Array(points[0...split]), tolerance: tolerance)
            let second = rdp(Array(points[split...]) + [points[0]], tolerance: tolerance)
            result = Array(first.dropLast()) + Array(second.dropLast())
            tolerance *= 1.5
        }
        if result.count > maximumCount {
            let stride = max(1, Int(ceil(Double(result.count) / Double(maximumCount))))
            result = result.enumerated().compactMap { $0.offset.isMultiple(of: stride) ? $0.element : nil }
        }
        return removingCollinear(result)
    }

    private nonisolated static func removingCollinear(_ points: [LocalPlanPoint]) -> [LocalPlanPoint] {
        guard points.count >= 3 else { return points }
        return points.indices.compactMap { index in
            let previous = points[(index + points.count - 1) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let cross = (current.x - previous.x) * (next.y - current.y)
                - (current.y - previous.y) * (next.x - current.x)
            return abs(cross) <= 1e-12 ? nil : current
        }
    }

    private nonisolated static func farthestIndex(
        from point: LocalPlanPoint, in points: [LocalPlanPoint]
    ) -> Int {
        points.indices.max {
            squaredDistance(point, points[$0]) < squaredDistance(point, points[$1])
        } ?? points.count / 2
    }

    private nonisolated static func rdp(
        _ points: [LocalPlanPoint], tolerance: Double
    ) -> [LocalPlanPoint] {
        guard points.count > 2 else { return points }
        let first = points[0]
        let last = points[points.count - 1]
        var maximumDistance = 0.0
        var split = 0
        for index in 1..<(points.count - 1) {
            let distance = distanceToSegment(points[index], first, last)
            if distance > maximumDistance {
                maximumDistance = distance
                split = index
            }
        }
        guard maximumDistance > tolerance else { return [first, last] }
        let left = rdp(Array(points[0...split]), tolerance: tolerance)
        let right = rdp(Array(points[split...]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }

    private nonisolated static func distanceToSegment(
        _ point: LocalPlanPoint, _ start: LocalPlanPoint, _ end: LocalPlanPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return sqrt(squaredDistance(point, start)) }
        let projection = min(1, max(0,
            ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        ))
        return hypot(point.x - (start.x + projection * dx), point.y - (start.y + projection * dy))
    }

    private nonisolated static func squaredDistance(
        _ first: LocalPlanPoint, _ second: LocalPlanPoint
    ) -> Double {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }
}
