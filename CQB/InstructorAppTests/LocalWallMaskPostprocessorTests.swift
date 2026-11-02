import Testing
@testable import InstructorApp

struct LocalWallMaskPostprocessorTests {
    @Test
    func removesOnlySmallInteriorBlockedComponents() throws {
        var mask = [UInt8](repeating: 0, count: 7 * 7)
        mask[index(0, 1)] = 1
        mask[index(3, 3)] = 1
        mask[index(5, 4)] = 1
        mask[index(5, 5)] = 1

        let result = try process(mask, minimumArea: 3, maximumHoleArea: 0)

        #expect(result.blocked[index(0, 1)] == 1)
        #expect(result.blocked[index(3, 3)] == 0)
        #expect(result.blocked[index(5, 4)] == 0)
        #expect(result.blocked[index(5, 5)] == 0)
        #expect(result.metrics.removedComponentCount == 2)
        #expect(result.metrics.removedCellCount == 3)
    }

    @Test
    func preservesThinCellsConnectedToMainWall() throws {
        var mask = [UInt8](repeating: 0, count: 7 * 7)
        for x in 1...5 { mask[index(x, 3)] = 1 }
        mask[index(5, 2)] = 1

        let result = try process(mask, minimumArea: 5, maximumHoleArea: 0)

        #expect(result.blocked == mask)
        #expect(result.metrics.removedCellCount == 0)
    }

    @Test
    func fillsOnlySmallEnclosedHoles() throws {
        var mask = [UInt8](repeating: 1, count: 7 * 7)
        for x in 0..<7 {
            mask[index(x, 0)] = 0
            mask[index(x, 6)] = 0
        }
        for y in 0..<7 {
            mask[index(0, y)] = 0
            mask[index(6, y)] = 0
        }
        mask[index(3, 3)] = 0

        let result = try process(mask, minimumArea: 0, maximumHoleArea: 1)

        #expect(result.blocked[index(3, 3)] == 1)
        #expect(result.blocked[index(0, 3)] == 0)
        #expect(result.metrics.filledHoleCount == 1)
        #expect(result.metrics.addedCellCount == 1)
    }

    @Test
    func preservesDoorSizedOpening() throws {
        var mask = [UInt8](repeating: 1, count: 7 * 7)
        for y in 0..<7 { mask[index(0, y)] = 0 }
        mask[index(1, 3)] = 0
        mask[index(2, 3)] = 0
        mask[index(3, 3)] = 0

        let result = try process(mask, minimumArea: 0, maximumHoleArea: 2)

        #expect(result.blocked[index(1, 3)] == 0)
        #expect(result.blocked[index(2, 3)] == 0)
        #expect(result.blocked[index(3, 3)] == 0)
        #expect(result.metrics.addedCellCount == 0)
    }

    @Test
    func obeysGlobalChangeBudget() throws {
        var mask = [UInt8](repeating: 0, count: 10 * 10)
        mask[22] = 1
        mask[44] = 1

        let result = try LocalWallMaskPostprocessor.process(
            blocked: mask,
            columns: 10,
            rows: 10,
            configuration: .init(
                minimumBlockedComponentAreaCells: 2,
                maximumHoleAreaCells: 0,
                maximumChangedFraction: 0.01
            )
        )

        #expect(result.metrics.changeBudgetCells == 1)
        #expect(result.metrics.removedCellCount == 1)
        #expect(result.blocked.filter { $0 == 1 }.count == 1)
    }

    @Test
    func straightensOnlySmallEndpointJitterOnLongBands() throws {
        let columns = 16
        let rows = 9
        var mask = [UInt8](repeating: 0, count: columns * rows)
        for x in 2...10 { mask[3 * columns + x] = 1 }
        for x in 3...11 { mask[4 * columns + x] = 1 }
        for x in 2...10 { mask[5 * columns + x] = 1 }

        let configuration = LocalWallMaskPostprocessor.Configuration(
            minimumBlockedComponentAreaCells: 0,
            maximumHoleAreaCells: 0,
            maximumChangedFraction: 1,
            minimumAxisAlignedLengthCells: 8,
            maximumAxisAlignedThicknessCells: 4,
            maximumAxisAlignedSnapDistanceCells: 1
        )
        let result = try LocalWallMaskPostprocessor.process(
            blocked: mask,
            columns: columns,
            rows: rows,
            configuration: configuration
        )
        let repeated = try LocalWallMaskPostprocessor.process(
            blocked: result.blocked,
            columns: columns,
            rows: rows,
            configuration: configuration
        )

        #expect(result.blocked[4 * columns + 2] == 1)
        #expect(result.blocked[4 * columns + 11] == 0)
        #expect(result.metrics.straightenedBandCount == 1)
        #expect(result.metrics.straightenedAddedCellCount == 1)
        #expect(result.metrics.straightenedRemovedCellCount == 1)
        #expect(repeated.blocked == result.blocked)
        #expect(repeated.metrics.changedCellCount == 0)
    }

    @Test
    func leavesDiagonalAndShortSegmentsUnchanged() throws {
        let columns = 12
        let rows = 12
        var mask = [UInt8](repeating: 0, count: columns * rows)
        for offset in 2...8 { mask[offset * columns + offset] = 1 }
        for x in 2...6 { mask[9 * columns + x] = 1 }

        let result = try LocalWallMaskPostprocessor.process(
            blocked: mask,
            columns: columns,
            rows: rows,
            configuration: .init(
                minimumBlockedComponentAreaCells: 0,
                maximumHoleAreaCells: 0,
                maximumChangedFraction: 1,
                minimumAxisAlignedLengthCells: 8,
                maximumAxisAlignedThicknessCells: 4,
                maximumAxisAlignedSnapDistanceCells: 1
            )
        )

        #expect(result.blocked == mask)
        #expect(result.metrics.straightenedBandCount == 0)
    }

    @Test
    func isIdempotent() throws {
        var mask = [UInt8](repeating: 1, count: 7 * 7)
        mask[index(3, 3)] = 0
        mask[index(0, 0)] = 0
        mask[index(1, 0)] = 0

        let first = try process(mask, minimumArea: 3, maximumHoleArea: 1)
        let second = try process(first.blocked, minimumArea: 3, maximumHoleArea: 1)

        #expect(second.blocked == first.blocked)
        #expect(second.metrics.changedCellCount == 0)
    }

    @Test
    func rejectsInvalidMask() {
        #expect(throws: LocalFloorPlanError.self) {
            try LocalWallMaskPostprocessor.process(
                blocked: [0, 2],
                columns: 2,
                rows: 1
            )
        }
    }

    private func process(
        _ mask: [UInt8],
        minimumArea: Int,
        maximumHoleArea: Int
    ) throws -> LocalWallMaskPostprocessor.Result {
        try LocalWallMaskPostprocessor.process(
            blocked: mask,
            columns: 7,
            rows: 7,
            configuration: .init(
                minimumBlockedComponentAreaCells: minimumArea,
                maximumHoleAreaCells: maximumHoleArea,
                maximumChangedFraction: 1
            )
        )
    }

    private func index(_ x: Int, _ y: Int) -> Int {
        y * 7 + x
    }
}
