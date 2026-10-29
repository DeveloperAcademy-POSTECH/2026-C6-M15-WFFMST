import Foundation
import ImageIO

@main
enum FloorPlanGeometryChecks {
    static func main() throws {
        let square = [point(0, 0), point(1, 0), point(1, 1), point(0, 1)]
        let base = grid(width: 100, height: 100)
        let diagonal = LocalEditStroke(mode: .block, points: [point(0.1, 0.1), point(0.8, 0.8)], normalizedDiameter: 0.0001)
        let thin = try resolve(base, [diagonal])
        // Every diagonal cell is covered even where the sampled disk misses all centers.
        for index in 5...40 { check(thin.blocked[index * 50 + index] == 1, "thin diagonal continuity") }
        let tap = LocalEditStroke(mode: .block, points: [point(0.21, 0.21)], normalizedDiameter: 0.0001)
        let tapped = try resolve(base, [tap])
        check(tapped.blocked.contains(1), "sub-cell tap fallback")
        let opening = LocalEditStroke(mode: .open, points: diagonal.points, normalizedDiameter: diagonal.normalizedDiameter)
        check(try resolve(base, [diagonal, opening]) == base, "later open overrides block")
        check(try resolve(base, [opening, diagonal]) == thin, "later block overrides open")
        var history = [diagonal, opening]
        history.removeLast()
        check(try resolve(base, history) == thin, "undo is deterministic replay")
        history.removeAll()
        check(try resolve(base, history) == base, "reset restores base")
        check(base.blocked.allSatisfy { $0 == 0 }, "resolver does not mutate base")

        let interior = [point(0.25, 0.25), point(0.75, 0.25), point(0.75, 0.75), point(0.25, 0.75)]
        let outlined = try LocalFloorPlanGeometry.resolve(base: base, width: 100, height: 100, strokes: [opening], outline: interior)
        check(outlined.blocked[0] == 1, "outside outline stays blocked despite opening")
        check(outlined.blocked[25 * 50 + 25] == 0, "inside outline remains open")
        try LocalFloorPlanGeometry.validateOutline(square)
        try LocalFloorPlanGeometry.validateOutline(Array(square.reversed()))
        try rejects("self intersection") {
            try LocalFloorPlanGeometry.validateOutline([point(0, 0), point(1, 1), point(0, 1), point(1, 0)])
        }
        try rejects("overlapping adjacent edges") {
            try LocalFloorPlanGeometry.validateOutline([point(0, 0), point(1, 0), point(0.5, 0), point(1, 1), point(0, 1)])
        }
        try rejects("zero area") { try LocalFloorPlanGeometry.validateOutline([point(0, 0), point(0.5, 0), point(1, 0)]) }
        try rejects("duplicate endpoint") { try LocalFloorPlanGeometry.validateOutline(square + [square[0]]) }
        try rejects("nonfinite outline") { try LocalFloorPlanGeometry.validateOutline([point(.nan, 0), point(1, 0), point(0, 1)]) }

        let odd = grid(width: 5, height: 7)
        let resolvedOdd = try LocalFloorPlanGeometry.resolve(base: odd, width: 5, height: 7, strokes: [], outline: [])
        check(resolvedOdd.columns == 3 && resolvedOdd.rows == 4, "ceil dimensions")
        for y in 0..<4 { check(resolvedOdd.blocked[y * 3 + 2] == 1, "last column center outside image") }
        for x in 0..<3 { check(resolvedOdd.blocked[9 + x] == 1, "last row center outside image") }
        check(resolvedOdd.blocked[0] == 0, "odd image interior unchanged")
        try rejects("invalid grid shape") {
            _ = try LocalFloorPlanGeometry.resolve(base: grid(width: 10, height: 10), width: 100, height: 100, strokes: [], outline: [])
        }
        try rejects("invalid cell value") {
            try LocalFloorPlanGeometry.validateGrid(LocalObstacleGrid(columns: 1, rows: 1, cellSizePixels: 2, blocked: [2]))
        }
        try rejects("invalid stroke coordinate") {
            _ = try resolve(base, [LocalEditStroke(mode: .block, points: [point(1.1, 0)], normalizedDiameter: 0.01)])
        }
        for diameter in [0.0, -1, 0.11, .infinity, .nan] {
            try rejects("invalid diameter") {
                _ = try resolve(base, [LocalEditStroke(mode: .block, points: [point(0.5, 0.5)], normalizedDiameter: diameter)])
            }
        }
        try rejects("empty stroke") {
            _ = try resolve(base, [LocalEditStroke(mode: .block, points: [], normalizedDiameter: 0.01)])
        }
        let scale = LocalPlanScale(a: point(0, 0), b: point(0.3, 0.4), meters: 10)
        check(try LocalFloorPlanGeometry.validateScale(scale, width: 100, height: 100) == 5, "scale pixels per meter")
        for meters in [0.0, -1, 1_001, .infinity, .nan, Double.leastNonzeroMagnitude] {
            try rejects("invalid meters") {
                _ = try LocalFloorPlanGeometry.validateScale(LocalPlanScale(a: scale.a, b: scale.b, meters: meters), width: 100, height: 100)
            }
        }
        try rejects("points too close") {
            _ = try LocalFloorPlanGeometry.validateScale(LocalPlanScale(a: point(0, 0), b: point(0.09, 0), meters: 1), width: 100, height: 100)
        }
        let png = try LocalFloorPlanMaskRenderer.pngData(grid: thin)
        let source = CGImageSourceCreateWithData(png as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        check(image.width == 50 && image.height == 50, "mask PNG dimensions")
        check(try resolve(base, [diagonal]) == thin, "preview/final deterministic replay")
        try cachedReplayMatchesFull()
        try automaticBlockedRegionSuggestion()
        print("PASS: 도면 격자 순서·얇은 획·자동 이동 불가 영역·축척·입력 검증·PNG 생성")
    }

    static func automaticBlockedRegionSuggestion() throws {
        let width = 120, height = 80
        let base = grid(width: width, height: height)
        let closedWithSmallGap = rgba(width: width, height: height) { x, y in
            let horizontal = (y == 10 || y == 69) && (10...109).contains(x)
            let vertical = (x == 10 || x == 109) && (10...69).contains(y)
            let gap = y == 10 && (56...63).contains(x)
            return (horizontal || vertical) && !gap
        }
        let suggestion = try LocalBlockedRegionAutoFill.suggest(
            base: base,
            rgba: closedWithSmallGap,
            width: width,
            height: height
        )
        let proposed = try require(suggestion, "a small exterior gap should be closed")
        check((3...128).contains(proposed.outline.count), "automatic outline must stay editable")
        check(proposed.confidence >= 0.45, "accepted outline must meet the confidence floor")
        try LocalFloorPlanGeometry.validateOutline(proposed.outline)
        let resolved = try LocalFloorPlanGeometry.resolve(
            base: base,
            width: width,
            height: height,
            strokes: [],
            outline: proposed.outline
        )
        check(resolved.blocked[0] == 1, "automatic outline must block the image exterior")
        check(resolved.blocked[20 * base.columns + 30] == 0, "automatic outline must preserve interior free space")

        let openShape = rgba(width: width, height: height) { x, y in
            ((x == 10 || x == 109) && (10...69).contains(y))
                || (y == 69 && (10...109).contains(x))
        }
        check(try LocalBlockedRegionAutoFill.suggest(
            base: base,
            rgba: openShape,
            width: width,
            height: height
        ) == nil, "a widely open shape must fall back to manual editing")

        let denseDrawing = rgba(width: width, height: height) { x, y in
            let outer = ((y == 8 || y == 71) && (8...111).contains(x))
                || ((x == 8 || x == 111) && (8...71).contains(y))
            let furniture = (16...103).contains(x) && (16...63).contains(y)
                && (x.isMultiple(of: 8) || y.isMultiple(of: 8))
            return outer || furniture
        }
        check(try LocalBlockedRegionAutoFill.suggest(
            base: base,
            rgba: denseDrawing,
            width: width,
            height: height
        ) != nil, "dense interior annotations must not suppress a valid outer boundary")

        var coloredDrawing = rgba(width: width, height: height) { _, _ in false }
        for y in 0..<height {
            for x in 0..<width {
                let outer = ((y == 8 || y == 71) && (8...111).contains(x))
                    || ((x == 8 || x == 111) && (8...71).contains(y))
                guard outer else { continue }
                let offset = (y * width + x) * 4
                coloredDrawing[offset] = 0
                coloredDrawing[offset + 1] = 190
                coloredDrawing[offset + 2] = 60
            }
        }
        check(try LocalBlockedRegionAutoFill.suggest(
            base: base,
            rgba: coloredDrawing,
            width: width,
            height: height
        ) != nil, "colored CAD outlines must remain valid boundary evidence")
    }

    static func cachedReplayMatchesFull() throws {
        // Odd dimensions, a populated base, overlapping block/open strokes, undo,
        // reset and changed/removed boundaries must all match uncached replay.
        let width = 101, height = 79
        var base = grid(width: width, height: height)
        for i in base.blocked.indices where i % 7 == 0 { base.blocked[i] = 1 }
        var cache = try LocalFloorPlanReplayCache(base: base, width: width, height: height)
        let outline = [point(0.2, 0.2), point(0.8, 0.2), point(0.8, 0.8), point(0.2, 0.8)]
        var history: [LocalEditStroke] = []
        func assertSame(_ strokes: [LocalEditStroke], _ polygon: [LocalPlanPoint]) throws {
            let expected = try LocalFloorPlanGeometry.resolve(base: base, width: width, height: height,
                                                              strokes: strokes, outline: polygon)
            let actual = try cache.resolve(strokes: strokes, outline: polygon)
            check(actual == expected, "incremental cache must match every cell of full replay")
        }
        for i in 0..<40 {
            history.append(LocalEditStroke(mode: i % 2 == 0 ? .block : .open,
                points: [point(Double(i % 11) / 10, 0.1), point(0.6, Double(i % 9) / 8)],
                normalizedDiameter: i % 3 == 0 ? 0.0001 : 0.04))
            try assertSame(history, outline)
        }
        history.removeLast()
        try assertSame(history, outline)
        try assertSame(history, []) // clipped cells must recover their true edit values
        try assertSame(history, Array(outline.reversed()))
        try rejects("cache invalid outline") { _ = try cache.resolve(strokes: history, outline: [point(0, 0)]) }
        try assertSame(history, outline) // failed update must not poison cache
        history.removeAll()
        try assertSame(history, outline)
        try assertSame(history, [])
        history.append(LocalEditStroke(mode: .open, points: [point(0.5, 0.5)], normalizedDiameter: 0.03))
        try assertSame(history, outline)
    }

    static func point(_ x: Double, _ y: Double) -> LocalPlanPoint { LocalPlanPoint(x: x, y: y) }
    static func grid(width: Int, height: Int) -> LocalObstacleGrid {
        let columns = (width + 1) / 2, rows = (height + 1) / 2
        return LocalObstacleGrid(columns: columns, rows: rows, cellSizePixels: 2, blocked: [UInt8](repeating: 0, count: columns * rows))
    }
    static func resolve(_ base: LocalObstacleGrid, _ strokes: [LocalEditStroke]) throws -> LocalObstacleGrid {
        try LocalFloorPlanGeometry.resolve(base: base, width: 100, height: 100, strokes: strokes, outline: [])
    }
    static func rgba(width: Int, height: Int, isLine: (Int, Int) -> Bool) -> [UInt8] {
        var result = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where isLine(x, y) {
                let offset = (y * width + x) * 4
                result[offset] = 0
                result[offset + 1] = 0
                result[offset + 2] = 0
            }
        }
        return result
    }
    static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw LocalFloorPlanError.invalid(message) }
        return value
    }
    static func check(_ condition: Bool, _ message: String) {
        if !condition { fatalError("FAIL: \(message)") }
    }
    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch is LocalFloorPlanError { return }
        fatalError("FAIL: accepted \(message)")
    }
}
