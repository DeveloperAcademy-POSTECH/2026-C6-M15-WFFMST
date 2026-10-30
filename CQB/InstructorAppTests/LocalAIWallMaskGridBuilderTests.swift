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
    func runsBundledBinaryModelEndToEnd() throws {
        let width = 512
        let height = 512
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
        guard let image = context.makeImage() else {
            Issue.record("테스트 입력 CGImage를 만들지 못했습니다.")
            return
        }

        let grid = try LocalAIWallDetector.grid(
            image: image,
            sourceWidth: width,
            sourceHeight: height,
            configuration: .baseline
        )

        #expect(grid.columns == 256)
        #expect(grid.rows == 256)
        #expect(grid.blocked.count == 256 * 256)
        #expect(grid.blocked.allSatisfy { $0 <= 1 })
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
