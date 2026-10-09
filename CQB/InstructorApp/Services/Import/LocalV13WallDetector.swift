import Foundation

/// floorplanPoC/FloorPlanWallDetector의 V13 규칙. 문과 통로의 빈틈을 임의로 메우지 않는다.
enum LocalV13WallDetector {
    nonisolated static func grid(rgba: [UInt8], width: Int, height: Int) throws -> LocalObstacleGrid {
        guard width > 0, height > 0, width <= 4_096, height <= 4_096,
              rgba.count == width * height * 4 else {
            throw LocalFloorPlanError.invalid("도면 픽셀 크기가 올바르지 않습니다.")
        }
        var ink = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width {
                let index = y * width + x
                let offset = index * 4
                let r = Int(rgba[offset]), g = Int(rgba[offset + 1]), b = Int(rgba[offset + 2])
                let gray = (r * 77 + g * 150 + b * 29) >> 8
                if gray < 205, max(r, g, b) - min(r, g, b) < 45 { ink[index] = 1 }
            }
        }
        var wall = [UInt8](repeating: 0, count: ink.count)
        let minimumLength = max(24, width / 65)
        try markRuns(ink, width: width, height: height, horizontal: true, minimumLength: minimumLength, output: &wall)
        try markRuns(ink, width: width, height: height, horizontal: false, minimumLength: minimumLength, output: &wall)
        if width >= 5, height >= 5 {
            for y in 2..<(height - 2) {
                try Task.checkCancellation()
                for x in 2..<(width - 2) {
                    let index = y * width + x
                    guard ink[index] == 1 else { continue }
                    var count = 0
                    for dy in -2...2 {
                        for dx in -2...2 { count += Int(ink[(y + dy) * width + x + dx]) }
                    }
                    if count >= 23 { wall[index] = 1 }
                }
            }
        }
        for _ in 0..<2 {
            let previous = wall
            if width > 2, height > 2 {
                for y in 1..<(height - 1) {
                    try Task.checkCancellation()
                    for x in 1..<(width - 1) {
                        let index = y * width + x
                        guard ink[index] == 1, previous[index] == 0 else { continue }
                        if previous[index - 1] == 1 || previous[index + 1] == 1 ||
                            previous[index - width] == 1 || previous[index + width] == 1 {
                            wall[index] = 1
                        }
                    }
                }
            }
        }
        let cellSize = 2
        let columns = (width + cellSize - 1) / cellSize
        let rows = (height + cellSize - 1) / cellSize
        var blocked = [UInt8](repeating: 0, count: columns * rows)
        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width where wall[y * width + x] == 1 {
                blocked[(y / cellSize) * columns + x / cellSize] = 1
            }
        }
        return LocalObstacleGrid(columns: columns, rows: rows, cellSizePixels: cellSize, blocked: blocked)
    }

    nonisolated private static func markRuns(
        _ ink: [UInt8], width: Int, height: Int, horizontal: Bool,
        minimumLength: Int, output: inout [UInt8]
    ) throws {
        let lineCount = horizontal ? height : width
        let lineLength = horizontal ? width : height
        let axisStep = horizontal ? 1 : width
        let acrossStep = horizontal ? width : 1
        guard lineCount > 4 else { return }
        for line in 2..<(lineCount - 2) {
            try Task.checkCancellation()
            let base = horizontal ? line * width : line
            var start = 0
            while start < lineLength {
                while start < lineLength && ink[base + start * axisStep] == 0 { start += 1 }
                guard start < lineLength else { break }
                var end = start
                var lastInk = start
                var supported = 0
                while end < lineLength {
                    let index = base + end * axisStep
                    if ink[index] == 1 {
                        lastInk = end
                        let acrossInk = Int(ink[index - acrossStep]) + Int(ink[index + acrossStep]) +
                            Int(ink[index - 2 * acrossStep]) + Int(ink[index + 2 * acrossStep])
                        if acrossInk >= 2 { supported += 1 }
                    } else if end - lastInk > 2 { break }
                    end += 1
                }
                let length = lastInk - start + 1
                if length >= minimumLength, Double(supported) / Double(length) >= 0.70 {
                    for position in start...lastInk {
                        let index = base + position * axisStep
                        if ink[index] == 1 { output[index] = 1 }
                    }
                }
                start = max(end, start + 1)
            }
        }
    }
}
