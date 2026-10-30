import Foundation

/// Core ML 원본 마스크를 보존하면서 작은 고립 영역과 내부 구멍만 제한적으로 정리합니다.
enum LocalWallMaskPostprocessor {
    nonisolated struct Configuration: Sendable, Equatable {
        let minimumBlockedComponentAreaCells: Int
        let maximumHoleAreaCells: Int
        let maximumChangedFraction: Double
        let minimumAxisAlignedLengthCells: Int
        let maximumAxisAlignedThicknessCells: Int
        let maximumAxisAlignedSnapDistanceCells: Int

        init(
            minimumBlockedComponentAreaCells: Int,
            maximumHoleAreaCells: Int,
            maximumChangedFraction: Double,
            minimumAxisAlignedLengthCells: Int = 0,
            maximumAxisAlignedThicknessCells: Int = 0,
            maximumAxisAlignedSnapDistanceCells: Int = 0
        ) {
            self.minimumBlockedComponentAreaCells = minimumBlockedComponentAreaCells
            self.maximumHoleAreaCells = maximumHoleAreaCells
            self.maximumChangedFraction = maximumChangedFraction
            self.minimumAxisAlignedLengthCells = minimumAxisAlignedLengthCells
            self.maximumAxisAlignedThicknessCells = maximumAxisAlignedThicknessCells
            self.maximumAxisAlignedSnapDistanceCells = maximumAxisAlignedSnapDistanceCells
        }

        static let conservative = Configuration(
            minimumBlockedComponentAreaCells: 8,
            maximumHoleAreaCells: 8,
            maximumChangedFraction: 0.005,
            minimumAxisAlignedLengthCells: 0,
            maximumAxisAlignedThicknessCells: 0,
            maximumAxisAlignedSnapDistanceCells: 0
        )

        static let axisAlignedExperiment = Configuration(
            minimumBlockedComponentAreaCells: 8,
            maximumHoleAreaCells: 8,
            maximumChangedFraction: 0.005,
            minimumAxisAlignedLengthCells: 24,
            maximumAxisAlignedThicknessCells: 12,
            maximumAxisAlignedSnapDistanceCells: 2
        )
    }

    nonisolated struct Metrics: Sendable, Equatable {
        let removedComponentCount: Int
        let removedCellCount: Int
        let filledHoleCount: Int
        let addedCellCount: Int
        let straightenedBandCount: Int
        let straightenedAddedCellCount: Int
        let straightenedRemovedCellCount: Int
        let changeBudgetCells: Int

        var changedCellCount: Int {
            removedCellCount + addedCellCount
                + straightenedAddedCellCount + straightenedRemovedCellCount
        }
    }

    nonisolated struct Result: Sendable, Equatable {
        let blocked: [UInt8]
        let metrics: Metrics
    }

    nonisolated private struct Component {
        let indices: [Int]
        let touchesBorder: Bool
    }

    nonisolated private struct Run {
        let row: Int
        let start: Int
        let end: Int

        var length: Int { end - start + 1 }
    }

    nonisolated private struct Band {
        var runs: [Run]
    }

    nonisolated private struct StraighteningMetrics {
        var bandCount = 0
        var addedCellCount = 0
        var removedCellCount = 0
    }

    nonisolated static func process(
        blocked: [UInt8],
        columns: Int,
        rows: Int,
        configuration: Configuration = .conservative
    ) throws -> Result {
        guard columns > 0, rows > 0,
              blocked.count == columns * rows,
              blocked.allSatisfy({ $0 <= 1 }),
              configuration.minimumBlockedComponentAreaCells >= 0,
              configuration.maximumHoleAreaCells >= 0,
              configuration.minimumAxisAlignedLengthCells >= 0,
              configuration.maximumAxisAlignedThicknessCells >= 0,
              configuration.maximumAxisAlignedSnapDistanceCells >= 0,
              configuration.maximumChangedFraction.isFinite,
              (0...1).contains(configuration.maximumChangedFraction) else {
            throw LocalFloorPlanError.invalid("벽 마스크 후처리 입력이 올바르지 않습니다.")
        }

        let requestedBudget = Int(
            (Double(blocked.count) * configuration.maximumChangedFraction).rounded(.down)
        )
        let changeBudget = configuration.maximumChangedFraction > 0
            ? max(1, requestedBudget)
            : 0
        var result = blocked
        var changedCells = 0
        var removedComponentCount = 0
        var removedCellCount = 0

        if configuration.minimumBlockedComponentAreaCells > 1, changeBudget > 0 {
            let candidates = components(
                in: result,
                matching: 1,
                columns: columns,
                rows: rows,
                usesDiagonalNeighbors: true
            )
            .filter {
                !$0.touchesBorder
                    && $0.indices.count < configuration.minimumBlockedComponentAreaCells
            }
            .sorted { $0.indices.count < $1.indices.count }

            for component in candidates {
                try Task.checkCancellation()
                guard changedCells + component.indices.count <= changeBudget else { continue }
                for index in component.indices { result[index] = 0 }
                changedCells += component.indices.count
                removedCellCount += component.indices.count
                removedComponentCount += 1
            }
        }

        var filledHoleCount = 0
        var addedCellCount = 0
        if configuration.maximumHoleAreaCells > 0, changedCells < changeBudget {
            let holes = components(
                in: result,
                matching: 0,
                columns: columns,
                rows: rows,
                usesDiagonalNeighbors: false
            )
            .filter {
                !$0.touchesBorder
                    && $0.indices.count <= configuration.maximumHoleAreaCells
            }
            .sorted { $0.indices.count < $1.indices.count }

            for hole in holes {
                try Task.checkCancellation()
                guard changedCells + hole.indices.count <= changeBudget else { continue }
                for index in hole.indices { result[index] = 1 }
                changedCells += hole.indices.count
                addedCellCount += hole.indices.count
                filledHoleCount += 1
            }
        }

        var straighteningMetrics = StraighteningMetrics()
        if configuration.minimumAxisAlignedLengthCells > 0,
           configuration.maximumAxisAlignedThicknessCells > 1,
           configuration.maximumAxisAlignedSnapDistanceCells > 0,
           changedCells < changeBudget {
            let horizontal = straightenHorizontalBands(
                in: result,
                columns: columns,
                rows: rows,
                minimumLength: configuration.minimumAxisAlignedLengthCells,
                maximumThickness: configuration.maximumAxisAlignedThicknessCells,
                maximumSnapDistance: configuration.maximumAxisAlignedSnapDistanceCells,
                changeBudget: changeBudget - changedCells
            )
            result = horizontal.values
            straighteningMetrics.bandCount += horizontal.metrics.bandCount
            straighteningMetrics.addedCellCount += horizontal.metrics.addedCellCount
            straighteningMetrics.removedCellCount += horizontal.metrics.removedCellCount
            changedCells += horizontal.metrics.addedCellCount + horizontal.metrics.removedCellCount

            if changedCells < changeBudget {
                let transposed = transpose(result, columns: columns, rows: rows)
                let vertical = straightenHorizontalBands(
                    in: transposed,
                    columns: rows,
                    rows: columns,
                    minimumLength: configuration.minimumAxisAlignedLengthCells,
                    maximumThickness: configuration.maximumAxisAlignedThicknessCells,
                    maximumSnapDistance: configuration.maximumAxisAlignedSnapDistanceCells,
                    changeBudget: changeBudget - changedCells
                )
                result = transpose(vertical.values, columns: rows, rows: columns)
                straighteningMetrics.bandCount += vertical.metrics.bandCount
                straighteningMetrics.addedCellCount += vertical.metrics.addedCellCount
                straighteningMetrics.removedCellCount += vertical.metrics.removedCellCount
            }
        }

        return Result(
            blocked: result,
            metrics: Metrics(
                removedComponentCount: removedComponentCount,
                removedCellCount: removedCellCount,
                filledHoleCount: filledHoleCount,
                addedCellCount: addedCellCount,
                straightenedBandCount: straighteningMetrics.bandCount,
                straightenedAddedCellCount: straighteningMetrics.addedCellCount,
                straightenedRemovedCellCount: straighteningMetrics.removedCellCount,
                changeBudgetCells: changeBudget
            )
        )
    }

    nonisolated private static func straightenHorizontalBands(
        in values: [UInt8],
        columns: Int,
        rows: Int,
        minimumLength: Int,
        maximumThickness: Int,
        maximumSnapDistance: Int,
        changeBudget: Int
    ) -> (values: [UInt8], metrics: StraighteningMetrics) {
        guard changeBudget > 0 else { return (values, StraighteningMetrics()) }
        let bands = horizontalBands(
            in: values,
            columns: columns,
            rows: rows,
            minimumLength: minimumLength,
            maximumThickness: maximumThickness,
            maximumSnapDistance: maximumSnapDistance
        )
        var output = values
        var metrics = StraighteningMetrics()
        var changedCells = 0

        for band in bands where band.runs.count > 1 {
            let starts = band.runs.map(\.start).sorted()
            let ends = band.runs.map(\.end).sorted()
            let targetStart = starts[starts.count / 2]
            let targetEnd = ends[ends.count / 2]
            var changedBand = false
            for run in band.runs {
                guard abs(run.start - targetStart) <= maximumSnapDistance,
                      abs(run.end - targetEnd) <= maximumSnapDistance else { continue }
                if targetStart < run.start {
                    for column in targetStart..<run.start where changedCells < changeBudget {
                        let index = run.row * columns + column
                        guard output[index] == 0 else { continue }
                        output[index] = 1
                        metrics.addedCellCount += 1
                        changedCells += 1
                        changedBand = true
                    }
                } else if targetStart > run.start {
                    for column in run.start..<targetStart where changedCells < changeBudget {
                        let index = run.row * columns + column
                        guard output[index] == 1,
                              !hasPerpendicularSupport(
                                at: index,
                                values: values,
                                columns: columns,
                                rows: rows
                              ) else { continue }
                        output[index] = 0
                        metrics.removedCellCount += 1
                        changedCells += 1
                        changedBand = true
                    }
                }
                if targetEnd > run.end {
                    for column in (run.end + 1)...targetEnd where changedCells < changeBudget {
                        let index = run.row * columns + column
                        guard output[index] == 0 else { continue }
                        output[index] = 1
                        metrics.addedCellCount += 1
                        changedCells += 1
                        changedBand = true
                    }
                } else if targetEnd < run.end {
                    for column in (targetEnd + 1)...run.end where changedCells < changeBudget {
                        let index = run.row * columns + column
                        guard output[index] == 1,
                              !hasPerpendicularSupport(
                                at: index,
                                values: values,
                                columns: columns,
                                rows: rows
                              ) else { continue }
                        output[index] = 0
                        metrics.removedCellCount += 1
                        changedCells += 1
                        changedBand = true
                    }
                }
            }
            if changedBand { metrics.bandCount += 1 }
            if changedCells >= changeBudget { break }
        }
        return (output, metrics)
    }

    nonisolated private static func horizontalBands(
        in values: [UInt8],
        columns: Int,
        rows: Int,
        minimumLength: Int,
        maximumThickness: Int,
        maximumSnapDistance: Int
    ) -> [Band] {
        var active: [Band] = []
        var completed: [Band] = []
        for row in 0..<rows {
            let runs = horizontalRuns(
                in: values,
                row: row,
                columns: columns,
                minimumLength: minimumLength
            )
            var next: [Band] = []
            var used = [Bool](repeating: false, count: active.count)
            for run in runs {
                var bestIndex: Int?
                var bestOverlap = 0
                for index in active.indices where !used[index] {
                    guard let previous = active[index].runs.last,
                          previous.row + 1 == row,
                          active[index].runs.count < maximumThickness,
                          abs(previous.start - run.start) <= maximumSnapDistance,
                          abs(previous.end - run.end) <= maximumSnapDistance else { continue }
                    let overlap = max(0, min(previous.end, run.end) - max(previous.start, run.start) + 1)
                    let minimumRunLength = min(previous.length, run.length)
                    guard overlap * 100 >= minimumRunLength * 85, overlap > bestOverlap else { continue }
                    bestIndex = index
                    bestOverlap = overlap
                }
                if let bestIndex {
                    used[bestIndex] = true
                    var band = active[bestIndex]
                    band.runs.append(run)
                    next.append(band)
                } else {
                    next.append(Band(runs: [run]))
                }
            }
            for index in active.indices where !used[index] {
                completed.append(active[index])
            }
            active = next
        }
        completed.append(contentsOf: active)
        return completed
    }

    nonisolated private static func horizontalRuns(
        in values: [UInt8],
        row: Int,
        columns: Int,
        minimumLength: Int
    ) -> [Run] {
        var runs: [Run] = []
        var column = 0
        while column < columns {
            guard values[row * columns + column] == 1 else {
                column += 1
                continue
            }
            let start = column
            while column + 1 < columns, values[row * columns + column + 1] == 1 {
                column += 1
            }
            if column - start + 1 >= minimumLength {
                runs.append(Run(row: row, start: start, end: column))
            }
            column += 1
        }
        return runs
    }

    nonisolated private static func hasPerpendicularSupport(
        at index: Int,
        values: [UInt8],
        columns: Int,
        rows: Int
    ) -> Bool {
        let row = index / columns
        let column = index % columns
        let above = row > 0 && values[(row - 1) * columns + column] == 1
        let below = row + 1 < rows && values[(row + 1) * columns + column] == 1
        return above && below
    }

    nonisolated private static func transpose(
        _ values: [UInt8],
        columns: Int,
        rows: Int
    ) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: values.count)
        for row in 0..<rows {
            for column in 0..<columns {
                result[column * rows + row] = values[row * columns + column]
            }
        }
        return result
    }

    nonisolated private static func components(
        in values: [UInt8],
        matching target: UInt8,
        columns: Int,
        rows: Int,
        usesDiagonalNeighbors: Bool
    ) -> [Component] {
        var visited = [Bool](repeating: false, count: values.count)
        var result: [Component] = []
        let offsets = usesDiagonalNeighbors
            ? (-1...1).flatMap { row in (-1...1).map { column in (column, row) } }
                .filter { $0 != (0, 0) }
            : [(-1, 0), (1, 0), (0, -1), (0, 1)]

        for start in values.indices where values[start] == target && !visited[start] {
            var indices = [start]
            var cursor = 0
            var touchesBorder = false
            visited[start] = true
            while cursor < indices.count {
                let index = indices[cursor]
                cursor += 1
                let column = index % columns
                let row = index / columns
                if column == 0 || column == columns - 1 || row == 0 || row == rows - 1 {
                    touchesBorder = true
                }
                for (columnOffset, rowOffset) in offsets {
                    let neighborColumn = column + columnOffset
                    let neighborRow = row + rowOffset
                    guard (0..<columns).contains(neighborColumn),
                          (0..<rows).contains(neighborRow) else { continue }
                    let neighbor = neighborRow * columns + neighborColumn
                    guard values[neighbor] == target, !visited[neighbor] else { continue }
                    visited[neighbor] = true
                    indices.append(neighbor)
                }
            }
            result.append(Component(indices: indices, touchesBorder: touchesBorder))
        }
        return result
    }
}
