import Foundation

@main
struct AIWallMaskGridChecks {
    static func main() throws {
        try probabilityThresholdCreatesBinaryMask()
        try classLogitsSelectWallClass()
        try letterboxContentMapsBackToSourceGrid()
        smallDisconnectedComponentsAreRemoved()
        try invalidValuesAreRejected()
        print("AI wall mask grid checks passed")
    }

    private static func smallDisconnectedComponentsAreRemoved() {
        let blocked: [UInt8] = [
            1, 0, 0, 0,
            0, 1, 1, 0,
            0, 1, 1, 0,
            0, 0, 0, 1,
        ]
        let filtered = LocalAIWallMaskGridBuilder.removingSmallComponents(
            from: blocked,
            columns: 4,
            rows: 4,
            minimumAreaCells: 3
        )
        expect(
            filtered == [
                1, 0, 0, 0,
                0, 1, 1, 0,
                0, 1, 1, 0,
                0, 0, 0, 1,
            ],
            "diagonal cells are part of the same 8-connected component"
        )

        let separated: [UInt8] = [
            1, 0, 0, 0,
            0, 0, 1, 1,
            0, 0, 1, 1,
            0, 0, 0, 0,
        ]
        expect(
            LocalAIWallMaskGridBuilder.removingSmallComponents(
                from: separated,
                columns: 4,
                rows: 4,
                minimumAreaCells: 3
            ) == [
                0, 0, 0, 0,
                0, 0, 1, 1,
                0, 0, 1, 1,
                0, 0, 0, 0,
            ],
            "components below the minimum area must be removed"
        )
    }

    private static func probabilityThresholdCreatesBinaryMask() throws {
        let mask = try LocalAIWallMaskGridBuilder.binaryMask(
            probabilities: [0.39, 0.4, 0.8, 0],
            width: 2,
            height: 2,
            threshold: 0.4
        )
        expect(mask == [0, 1, 1, 0], "probability threshold must include equal values")
    }

    private static func classLogitsSelectWallClass() throws {
        // Four classes, two pixels, channel-major. Wall class is index 1.
        let logits: [Float] = [
            4, 0,
            1, 5,
            0, 1,
            0, 2,
        ]
        let mask = try LocalAIWallMaskGridBuilder.binaryMask(
            classLogits: logits,
            classCount: 4,
            width: 2,
            height: 1,
            wallClassIndex: 1
        )
        expect(mask == [0, 1], "argmax must select only the wall class")
    }

    private static func letterboxContentMapsBackToSourceGrid() throws {
        var mask = [UInt8](repeating: 0, count: 4 * 4)
        mask[1 * 4 + 1] = 1
        let grid = try LocalAIWallMaskGridBuilder.grid(
            binaryMask: mask,
            maskWidth: 4,
            maskHeight: 4,
            contentX: 1,
            contentY: 0,
            contentWidth: 2,
            contentHeight: 4,
            sourceWidth: 4,
            sourceHeight: 4
        )
        expect(grid.columns == 2 && grid.rows == 2, "source must become a 2px grid")
        expect(grid.blocked == [1, 0, 0, 0], "letterbox padding must not shift wall cells")
    }

    private static func invalidValuesAreRejected() throws {
        expectThrows("NaN probability must be rejected") {
            _ = try LocalAIWallMaskGridBuilder.binaryMask(
                probabilities: [.nan], width: 1, height: 1, threshold: 0.4
            )
        }
        expectThrows("non-binary masks must be rejected") {
            _ = try LocalAIWallMaskGridBuilder.grid(
                binaryMask: [2],
                maskWidth: 1,
                maskHeight: 1,
                contentX: 0,
                contentY: 0,
                contentWidth: 1,
                contentHeight: 1,
                sourceWidth: 2,
                sourceHeight: 2
            )
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    private static func expectThrows(_ message: String, _ operation: () throws -> Void) {
        do {
            try operation()
            fatalError(message)
        } catch {}
    }
}
