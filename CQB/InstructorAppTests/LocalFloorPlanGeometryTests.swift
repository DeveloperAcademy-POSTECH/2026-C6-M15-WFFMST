import Testing
@testable import InstructorApp

struct LocalFloorPlanGeometryTests {
    @Test
    func userDeletionOverridesGeneratedOutsideMask() throws {
        let base = LocalObstacleGrid(
            columns: 4,
            rows: 4,
            cellSizePixels: 1,
            blocked: .init(repeating: 0, count: 16)
        )
        let outline = [
            LocalPlanPoint(x: 0.25, y: 0.25),
            LocalPlanPoint(x: 0.75, y: 0.25),
            LocalPlanPoint(x: 0.75, y: 0.75),
            LocalPlanPoint(x: 0.25, y: 0.75),
        ]
        let deletion = LocalEditAction.region(LocalEditRegion(
            mode: .open,
            points: [
                LocalPlanPoint(x: 0, y: 0),
                LocalPlanPoint(x: 0.25, y: 0),
                LocalPlanPoint(x: 0.25, y: 0.25),
                LocalPlanPoint(x: 0, y: 0.25),
            ]
        ))

        let result = try LocalFloorPlanGeometry.resolve(
            base: base,
            width: 4,
            height: 4,
            edits: [deletion],
            outline: outline
        )

        #expect(result.blocked[0] == 0)
        #expect(result.blocked[3] == 1)
    }

    @Test
    func replayCacheKeepsUserDeletionWhenAppendingEdits() throws {
        let base = LocalObstacleGrid(
            columns: 4,
            rows: 4,
            cellSizePixels: 1,
            blocked: .init(repeating: 0, count: 16)
        )
        let outline = [
            LocalPlanPoint(x: 0.25, y: 0.25),
            LocalPlanPoint(x: 0.75, y: 0.25),
            LocalPlanPoint(x: 0.75, y: 0.75),
            LocalPlanPoint(x: 0.25, y: 0.75),
        ]
        let deletion = LocalEditAction.region(LocalEditRegion(
            mode: .open,
            points: [
                LocalPlanPoint(x: 0, y: 0),
                LocalPlanPoint(x: 0.25, y: 0),
                LocalPlanPoint(x: 0.25, y: 0.25),
                LocalPlanPoint(x: 0, y: 0.25),
            ]
        ))
        let addition = LocalEditAction.region(LocalEditRegion(
            mode: .block,
            points: [
                LocalPlanPoint(x: 0.25, y: 0.25),
                LocalPlanPoint(x: 0.5, y: 0.25),
                LocalPlanPoint(x: 0.5, y: 0.5),
                LocalPlanPoint(x: 0.25, y: 0.5),
            ]
        ))
        var cache = try LocalFloorPlanReplayCache(base: base, width: 4, height: 4)

        _ = try cache.resolve(edits: [deletion], outline: outline)
        let result = try cache.resolve(edits: [deletion, addition], outline: outline)

        #expect(result.blocked[0] == 0)
        #expect(result.blocked[5] == 1)
    }
}
