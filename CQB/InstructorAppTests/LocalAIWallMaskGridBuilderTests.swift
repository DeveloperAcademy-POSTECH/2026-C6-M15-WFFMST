import CoreGraphics
import CoreML
import CoreVideo
import Testing
@testable import InstructorApp

struct LocalAIWallMaskGridBuilderTests {
    @Test
    func flipsOnlyTheCompletedGridRows() {
        let values: [UInt8] = [
            1, 2,
            3, 4,
            5, 6,
        ]

        let flipped = LocalAIWallMaskGridBuilder.flippingRows(
            values,
            columns: 2,
            rows: 3
        )

        #expect(flipped == [5, 6, 3, 4, 1, 2])
    }

    @Test
    func readsBinaryFloat16OutputUsingItsStrides() throws {
        let output = try MLMultiArray(
            shape: [1, 1, 2, 3],
            dataType: .float16
        )
        let values: [Float16] = [0, 0.25, 0.5, 0.75, 1, 0.125]
        let pointer = output.dataPointer.bindMemory(to: Float16.self, capacity: output.count)
        for (index, value) in values.enumerated() {
            pointer[index] = value
        }

        let probabilities = try LocalAIWallMaskGridBuilder.blockedProbabilities(
            from: output,
            width: 3,
            height: 2
        )

        #expect(probabilities == values.map(Float.init))
    }

    @Test
    func rejectsLegacyFourClassOutput() throws {
        let output = try MLMultiArray(
            shape: [1, 4, 2, 3],
            dataType: .float16
        )

        #expect(throws: LocalFloorPlanError.self) {
            try LocalAIWallMaskGridBuilder.blockedProbabilities(
                from: output,
                width: 3,
                height: 2
            )
        }
    }

    @Test
    func binaryMaskUsesInclusiveThreshold() throws {
        let mask = try LocalAIWallMaskGridBuilder.binaryMask(
            probabilities: [0.49, 0.5, 0.9, 0.1],
            width: 2,
            height: 2,
            threshold: 0.5
        )

        #expect(mask == [0, 1, 1, 0])
    }

    @Test
    func usesCPUOnlyForSimulatorInference() {
#if targetEnvironment(simulator)
        #expect(LocalAIWallDetector.modelComputeUnits == .cpuOnly)
#else
        #expect(LocalAIWallDetector.modelComputeUnits == .all)
#endif
    }

    @Test
    func rejectsAnEmptyInferenceResult() {
        #expect(throws: LocalFloorPlanError.self) {
            try LocalAIWallDetector.validateInference([0, 0, 0, 0])
        }
    }

    @Test
    func acceptsAnInferenceResultContainingWallProbability() throws {
        try LocalAIWallDetector.validateInference([0, 0.25, 0, 0])
    }

    @Test
    func compactFloorPlanProducesInternalWallCells() throws {
        let width = 768
        let height = 768
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("테스트 입력 CGContext를 만들지 못했습니다.")
            return
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
        context.setLineWidth(12)
        context.stroke(CGRect(x: 72, y: 72, width: 624, height: 624))
        context.move(to: CGPoint(x: 384, y: 72))
        context.addLine(to: CGPoint(x: 384, y: 300))
        context.move(to: CGPoint(x: 384, y: 360))
        context.addLine(to: CGPoint(x: 384, y: 696))
        context.move(to: CGPoint(x: 72, y: 384))
        context.addLine(to: CGPoint(x: 300, y: 384))
        context.move(to: CGPoint(x: 360, y: 384))
        context.addLine(to: CGPoint(x: 696, y: 384))
        context.strokePath()
        guard let image = context.makeImage() else {
            Issue.record("테스트 입력 CGImage를 만들지 못했습니다.")
            return
        }

        let grid = try LocalAIWallDetector.grid(
            image: image,
            sourceWidth: width,
            sourceHeight: height,
            configuration: .cropContrastTiles
        )

        #expect(grid.columns == 384)
        #expect(grid.rows == 384)
        #expect(grid.blocked.count == 384 * 384)
        #expect(grid.blocked.allSatisfy { $0 <= 1 })
        let wallCellCount = grid.blocked.reduce(0) { $0 + Int($1) }
        #expect((1_000...36_864).contains(wallCellCount))
    }

    @Test
    func highResolutionCameraStyleFloorPlanProducesWallsAndOutline() throws {
        let width = 2_048
        let height = 1_536
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let image = pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return nil }
            context.setFillColor(CGColor(red: 0.94, green: 0.93, blue: 0.89, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(gray: 0.99, alpha: 1))
            context.fill(CGRect(x: 180, y: 140, width: 1_688, height: 1_256))
            context.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
            context.setLineWidth(20)
            context.stroke(CGRect(x: 220, y: 180, width: 1_608, height: 1_176))
            for x in stride(from: 488, through: 1_560, by: 268) {
                context.move(to: CGPoint(x: x, y: 180))
                context.addLine(to: CGPoint(x: x, y: 720))
                context.move(to: CGPoint(x: x, y: 810))
                context.addLine(to: CGPoint(x: x, y: 1_356))
            }
            context.move(to: CGPoint(x: 220, y: 768))
            context.addLine(to: CGPoint(x: 900, y: 768))
            context.move(to: CGPoint(x: 990, y: 768))
            context.addLine(to: CGPoint(x: 1_828, y: 768))
            context.strokePath()
            return context.makeImage()
        }
        guard let image else {
            Issue.record("고해상도 카메라형 테스트 이미지를 만들지 못했습니다.")
            return
        }

        let grid = try LocalAIWallDetector.grid(
            image: image,
            sourceWidth: width,
            sourceHeight: height
        )
        let suggestion = try LocalBlockedRegionAutoFill.suggest(
            base: grid,
            rgba: pixels,
            width: width,
            height: height
        )

        #expect(grid.blocked.contains(1))
        #expect(suggestion?.outline.count ?? 0 >= 3)
    }

    @Test
    func modelInputKeepsTopAndBottomRowsInImageOrder() throws {
        let width = LocalAIWallDetector.inputSize
        let height = LocalAIWallDetector.inputSize
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let isTopHalf = y < height / 2
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = isTopHalf ? 255 : 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = isTopHalf ? 0 : 255
                pixels[offset + 3] = 255
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            Issue.record("상하 방향 테스트 이미지를 만들지 못했습니다.")
            return
        }

        let buffer = try LocalAIWallDetector.makePixelBuffer(
            image: image,
            letterbox: (x: 0, y: 0, width: width, height: height)
        )
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            Issue.record("Core ML 입력 버퍼를 읽지 못했습니다.")
            return
        }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let centerX = width / 2
        let top = centerX * 4
        let bottom = (height - 1) * bytesPerRow + centerX * 4

        // Pixel buffer는 BGRA이므로 빨간색은 R(2), 파란색은 B(0)가 더 크다.
        #expect(bytes[top + 2] > bytes[top])
        #expect(bytes[bottom] > bytes[bottom + 2])
    }

}
