import CoreGraphics
import CoreML
import CoreVideo
import Foundation

/// 512px U-Net 모델을 실행하고 벽·창문 클래스를 기존 장애물 격자로 변환합니다.
enum LocalAIWallDetector {
    nonisolated static let inputSize = 512
    nonisolated private static let classCount = 4
    nonisolated private static let blockedClassIndices: Set<Int> = [1, 3] // wall, window

    nonisolated static func grid(
        image: CGImage,
        sourceWidth: Int,
        sourceHeight: Int
    ) throws -> LocalObstacleGrid {
        try Task.checkCancellation()
        guard image.width == sourceWidth, image.height == sourceHeight,
              sourceWidth > 0, sourceHeight > 0 else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 입력 이미지의 크기가 올바르지 않습니다.")
        }

        let letterbox = letterboxSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        let pixelBuffer = try makePixelBuffer(image: image, letterbox: letterbox)
        let model = try loadModel()
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        let prediction = try model.prediction(from: input)
        guard let logits = prediction.featureValue(for: "classLogits")?.multiArrayValue else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 모델의 classLogits 출력이 없습니다.")
        }
        let mask = try binaryMask(logits: logits)
        return try LocalAIWallMaskGridBuilder.grid(
            binaryMask: mask,
            maskWidth: inputSize,
            maskHeight: inputSize,
            contentX: letterbox.x,
            contentY: letterbox.y,
            contentWidth: letterbox.width,
            contentHeight: letterbox.height,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
    }

    nonisolated private static func loadModel() throws -> MLModel {
        guard let modelURL = Bundle.main.url(
            forResource: "FloorPlanWallSegmentation",
            withExtension: "mlmodelc"
        ) else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 모델을 앱에서 찾지 못했습니다.")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    nonisolated private static func letterboxSize(
        sourceWidth: Int,
        sourceHeight: Int
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        let scale = min(
            Double(inputSize) / Double(sourceWidth),
            Double(inputSize) / Double(sourceHeight)
        )
        let width = min(inputSize, max(1, Int((Double(sourceWidth) * scale).rounded())))
        let height = min(inputSize, max(1, Int((Double(sourceHeight) * scale).rounded())))
        return (
            x: (inputSize - width) / 2,
            y: (inputSize - height) / 2,
            width: width,
            height: height
        )
    }

    nonisolated private static func makePixelBuffer(
        image: CGImage,
        letterbox: (x: Int, y: Int, width: Int, height: Int)
    ) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            inputSize,
            inputSize,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 입력 버퍼를 만들지 못했습니다.")
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: baseAddress,
                width: inputSize,
                height: inputSize,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 입력 이미지를 그리지 못했습니다.")
        }

        // 학습 설정과 동일하게 letterbox 여백을 ImageNet 평균 RGB로 채웁니다.
        context.setFillColor(CGColor(red: 0.485, green: 0.456, blue: 0.406, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: letterbox.x,
                y: inputSize - letterbox.y - letterbox.height,
                width: letterbox.width,
                height: letterbox.height
            )
        )
        return buffer
    }

    nonisolated private static func binaryMask(logits: MLMultiArray) throws -> [UInt8] {
        let expectedShape = [1, classCount, inputSize, inputSize]
        guard logits.dataType == .float16,
              logits.shape.map(\.intValue) == expectedShape,
              logits.strides.count == expectedShape.count else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 모델의 출력 형식이 올바르지 않습니다.")
        }
        let strides = logits.strides.map(\.intValue)
        guard strides.allSatisfy({ $0 >= 0 }) else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 모델의 출력 stride가 올바르지 않습니다.")
        }
        let values = logits.dataPointer.bindMemory(to: Float16.self, capacity: logits.count)
        var mask = [UInt8](repeating: 0, count: inputSize * inputSize)
        for y in 0..<inputSize {
            try Task.checkCancellation()
            for x in 0..<inputSize {
                var selectedClass = 0
                var selectedValue = Float(values[y * strides[2] + x * strides[3]])
                guard selectedValue.isFinite else {
                    throw LocalFloorPlanError.invalid("AI 벽 추출 결과에 유효하지 않은 값이 있습니다.")
                }
                for classIndex in 1..<classCount {
                    let offset = classIndex * strides[1] + y * strides[2] + x * strides[3]
                    let value = Float(values[offset])
                    guard value.isFinite else {
                        throw LocalFloorPlanError.invalid("AI 벽 추출 결과에 유효하지 않은 값이 있습니다.")
                    }
                    if value > selectedValue {
                        selectedClass = classIndex
                        selectedValue = value
                    }
                }
                mask[y * inputSize + x] = blockedClassIndices.contains(selectedClass) ? 1 : 0
            }
        }
        return mask
    }
}
