import CoreGraphics
import CoreML
import CoreVideo
import Foundation

/// 전처리된 전역·타일 입력으로 512px 이진 U-Net을 실행하고 장애물 확률을 격자로 변환합니다.
enum LocalAIWallDetector {
    nonisolated enum LineProcessing: Sendable {
        case original
        case highContrast
        case highContrastDilated
    }

    nonisolated enum TileStrategy: Sendable {
        case none
        case fixedOverlap
        case equalGrid(Int)
    }

    nonisolated struct Configuration: Sendable {
        let cropsEmptyMargins: Bool
        let lineProcessing: LineProcessing
        let tileStrategy: TileStrategy
        let blockedThreshold: Float
        let minimumComponentAreaCells: Int

        static let baseline = Configuration(
            cropsEmptyMargins: false,
            lineProcessing: .original,
            tileStrategy: .none,
            blockedThreshold: 0.5,
            minimumComponentAreaCells: 0
        )
        static let cropOriginalTiles = Configuration(
            cropsEmptyMargins: true,
            lineProcessing: .original,
            tileStrategy: .fixedOverlap,
            blockedThreshold: 0.5,
            minimumComponentAreaCells: 0
        )
        static let cropContrastTiles = contrastTiles(blockedThreshold: 0.6)
        static let cropLineTiles = lineTiles()

        static func contrastTiles(
            blockedThreshold: Float = 0.5,
            minimumComponentAreaCells: Int = 0
        ) -> Configuration {
            Configuration(
                cropsEmptyMargins: true,
                lineProcessing: .highContrast,
                tileStrategy: .fixedOverlap,
                blockedThreshold: blockedThreshold,
                minimumComponentAreaCells: minimumComponentAreaCells
            )
        }

        static func lineTiles(
            blockedThreshold: Float = 0.5,
            minimumComponentAreaCells: Int = 0
        ) -> Configuration {
            Configuration(
                cropsEmptyMargins: true,
                lineProcessing: .highContrastDilated,
                tileStrategy: .fixedOverlap,
                blockedThreshold: blockedThreshold,
                minimumComponentAreaCells: minimumComponentAreaCells
            )
        }

        static let equalGrid2 = equalGrid(2)
        static let equalGrid3 = equalGrid(3)
        static let equalGrid4 = equalGrid(4)

        private static func equalGrid(_ divisions: Int) -> Configuration {
            Configuration(
                cropsEmptyMargins: true,
                lineProcessing: .highContrastDilated,
                tileStrategy: .equalGrid(divisions),
                blockedThreshold: 0.5,
                minimumComponentAreaCells: 0
            )
        }
    }

    nonisolated static let inputSize = 512
    nonisolated private static let tileOverlap = 128
    nonisolated private static let globalWeight: Float = 0.5

    nonisolated static func grid(
        image: CGImage,
        sourceWidth: Int,
        sourceHeight: Int,
        configuration: Configuration = .cropContrastTiles
    ) throws -> LocalObstacleGrid {
        try Task.checkCancellation()
        guard image.width == sourceWidth, image.height == sourceHeight,
              sourceWidth > 0, sourceHeight > 0 else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 입력 이미지의 크기가 올바르지 않습니다.")
        }

        // 원본 저장 이미지는 유지하고 선택한 선 전처리는 모델 입력에만 적용합니다.
        let preprocessed = try preprocess(image: image, configuration: configuration)
        let crop = preprocessed.crop
        let model = try loadModel()
        let columns = sourceWidth / LocalV13WallDetector.cellSizePixels
        let rows = sourceHeight / LocalV13WallDetector.cellSizePixels
        var weightedProbabilities = [Float](repeating: 0, count: columns * rows)
        var weights = [Float](repeating: 0, count: columns * rows)

        // 전역 입력은 방과 벽의 전체 배치 맥락을 유지합니다.
        let global = try predict(model: model, image: preprocessed.image, region: crop)
        try accumulate(
            global, region: crop,
            sourceWidth: sourceWidth, sourceHeight: sourceHeight,
            columns: columns, rows: rows, weight: globalWeight,
            probabilities: &weightedProbabilities, weights: &weights
        )

        // 타일 추론은 큰 도면의 얇은 선이 전역 축소 과정에서 사라지는 문제를 줄입니다.
        let tiles = tileRegions(in: crop, strategy: configuration.tileStrategy)
        for tile in tiles where tile != crop || tiles.count > 1 {
            try Task.checkCancellation()
            let prediction = try predict(model: model, image: preprocessed.image, region: tile)
            try accumulate(
                prediction, region: tile,
                sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                columns: columns, rows: rows, weight: 1,
                probabilities: &weightedProbabilities, weights: &weights
            )
        }

        var blocked = zip(weightedProbabilities, weights).map { probability, weight in
            weight > 0 && probability / weight >= configuration.blockedThreshold ? UInt8(1) : UInt8(0)
        }
        // 전역·타일 결합 결과는 bottom-origin 행 순서다. 앱의 이미지·편집·저장 계약은
        // top-left row-major이므로, 타일별 결과가 아닌 완성된 격자를 여기서 한 번만 뒤집는다.
        blocked = LocalAIWallMaskGridBuilder.flippingRows(
            blocked,
            columns: columns,
            rows: rows
        )
        if configuration.minimumComponentAreaCells > 0 {
            blocked = LocalAIWallMaskGridBuilder.removingSmallComponents(
                from: blocked,
                columns: columns,
                rows: rows,
                minimumAreaCells: configuration.minimumComponentAreaCells
            )
        }
        return LocalObstacleGrid(
            columns: columns,
            rows: rows,
            cellSizePixels: LocalV13WallDetector.cellSizePixels,
            blocked: blocked
        )
    }

    nonisolated private struct PreprocessedImage {
        let image: CGImage
        let crop: CGRect
    }

    nonisolated private struct Prediction {
        let blockedProbabilities: [Float]
        let letterbox: (x: Int, y: Int, width: Int, height: Int)
    }

    nonisolated private static func loadModel() throws -> MLModel {
        guard let modelURL = Bundle.main.url(
            forResource: "BinaryWallSegmentation",
            withExtension: "mlmodelc"
        ) else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 모델을 앱에서 찾지 못했습니다.")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    nonisolated private static func preprocess(
        image: CGImage,
        configuration: Configuration
    ) throws -> PreprocessedImage {
        let width = image.width
        let height = image.height
        var grayscale = [UInt8](repeating: 255, count: width * height)
        let rendered = grayscale.withUnsafeMutableBytes { bytes -> Bool in
            let colorSpace = CGColorSpaceCreateDeviceGray()
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 입력 픽셀을 읽지 못했습니다.")
        }

        // 내용 픽셀의 경계에 여유를 더해, 흰 여백만 제외하고 도면 선은 자르지 않습니다.
        let crop = configuration.cropsEmptyMargins
            ? foregroundCrop(grayscale: grayscale, width: width, height: height)
            : CGRect(x: 0, y: 0, width: width, height: height)
        guard configuration.lineProcessing != .original else {
            return PreprocessedImage(image: image, crop: crop)
        }

        for index in grayscale.indices {
            let luminance = Int(grayscale[index])
            // 거의 흰 배경은 흰색으로 고정하고 나머지는 대비를 넓혀 옅은 CAD 선을 보존합니다.
            let contrasted = luminance >= 245
                ? 255
                : max(0, min(255, (luminance - 24) * 255 / 221))
            grayscale[index] = UInt8(contrasted)
        }
        guard configuration.lineProcessing == .highContrastDilated else {
            return PreprocessedImage(
                image: try grayscaleImage(grayscale, width: width, height: height),
                crop: crop
            )
        }

        var preserved = grayscale
        if width > 2, height > 2 {
            for y in 1..<(height - 1) {
                try Task.checkCancellation()
                for x in 1..<(width - 1) {
                    var darkest = UInt8.max
                    for offsetY in -1...1 {
                        for offsetX in -1...1 {
                            darkest = min(darkest, grayscale[(y + offsetY) * width + x + offsetX])
                        }
                    }
                    preserved[y * width + x] = darkest
                }
            }
        }

        return PreprocessedImage(
            image: try grayscaleImage(preserved, width: width, height: height),
            crop: crop
        )
    }

    nonisolated private static func grayscaleImage(
        _ pixels: [UInt8],
        width: Int,
        height: Int
    ) throws -> CGImage {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let processedImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 전처리 이미지를 만들지 못했습니다.")
        }
        return processedImage
    }

    nonisolated private static func foregroundCrop(
        grayscale: [UInt8],
        width: Int,
        height: Int
    ) -> CGRect {
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where grayscale[y * width + x] < 245 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }
        let margin = max(16, Int(Double(max(width, height)) * 0.02))
        let x = max(0, minX - margin)
        let y = max(0, minY - margin)
        let right = min(width, maxX + margin + 1)
        let bottom = min(height, maxY + margin + 1)
        return CGRect(x: x, y: y, width: right - x, height: bottom - y)
    }

    nonisolated private static func tileRegions(
        in crop: CGRect,
        strategy: TileStrategy
    ) -> [CGRect] {
        switch strategy {
        case .none:
            return []
        case .fixedOverlap:
            return fixedTileRegions(in: crop)
        case .equalGrid(let divisions):
            return equalGridRegions(in: crop, divisions: divisions)
        }
    }

    nonisolated private static func fixedTileRegions(in crop: CGRect) -> [CGRect] {
        let cropWidth = Int(crop.width)
        let cropHeight = Int(crop.height)
        guard cropWidth > inputSize || cropHeight > inputSize else { return [crop] }
        let xStarts = tileStarts(length: cropWidth)
        let yStarts = tileStarts(length: cropHeight)
        return yStarts.flatMap { relativeY in
            xStarts.map { relativeX in
                CGRect(
                    x: Int(crop.minX) + relativeX,
                    y: Int(crop.minY) + relativeY,
                    width: min(inputSize, cropWidth - relativeX),
                    height: min(inputSize, cropHeight - relativeY)
                )
            }
        }
    }

    nonisolated private static func equalGridRegions(
        in crop: CGRect,
        divisions: Int
    ) -> [CGRect] {
        guard divisions > 0 else { return [] }
        let cropX = Int(crop.minX)
        let cropY = Int(crop.minY)
        let cropWidth = Int(crop.width)
        let cropHeight = Int(crop.height)
        return (0..<divisions).flatMap { row in
            (0..<divisions).map { column in
                let x0 = cropX + cropWidth * column / divisions
                let x1 = cropX + cropWidth * (column + 1) / divisions
                let y0 = cropY + cropHeight * row / divisions
                let y1 = cropY + cropHeight * (row + 1) / divisions
                return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            }
        }
    }

    nonisolated private static func tileStarts(length: Int) -> [Int] {
        guard length > inputSize else { return [0] }
        let step = inputSize - tileOverlap
        var starts = Array(stride(from: 0, through: max(0, length - inputSize), by: step))
        let finalStart = length - inputSize
        if starts.last != finalStart { starts.append(finalStart) }
        return starts
    }

    nonisolated private static func predict(model: MLModel, image: CGImage, region: CGRect) throws -> Prediction {
        guard let cropped = image.cropping(to: region) else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 입력 영역을 자르지 못했습니다.")
        }
        let letterbox = letterboxSize(sourceWidth: cropped.width, sourceHeight: cropped.height)
        let pixelBuffer = try makePixelBuffer(image: cropped, letterbox: letterbox)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        let output = try model.prediction(from: input)
        guard let probabilities = output.featureValue(for: "blockedProbability")?.multiArrayValue else {
            throw LocalFloorPlanError.invalid("AI 벽 추출 모델의 blockedProbability 출력이 없습니다.")
        }
        return Prediction(
            blockedProbabilities: try LocalAIWallMaskGridBuilder.blockedProbabilities(
                from: probabilities,
                width: inputSize,
                height: inputSize
            ),
            letterbox: letterbox
        )
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

    nonisolated static func makePixelBuffer(
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

    nonisolated private static func accumulate(
        _ prediction: Prediction,
        region: CGRect,
        sourceWidth: Int,
        sourceHeight: Int,
        columns: Int,
        rows: Int,
        weight: Float,
        probabilities: inout [Float],
        weights: inout [Float]
    ) throws {
        let cellSize = LocalV13WallDetector.cellSizePixels
        let firstColumn = max(0, Int(region.minX) / cellSize)
        let finalColumn = min(columns - 1, (Int(region.maxX) - 1) / cellSize)
        let firstRow = max(0, Int(region.minY) / cellSize)
        let finalRow = min(rows - 1, (Int(region.maxY) - 1) / cellSize)
        guard firstColumn <= finalColumn, firstRow <= finalRow else { return }

        for row in firstRow...finalRow {
            try Task.checkCancellation()
            let sourceY = min(sourceHeight - 1, row * cellSize + cellSize / 2)
            guard Double(sourceY) >= region.minY, Double(sourceY) < region.maxY else { continue }
            let localY = Double(sourceY) - region.minY
            let modelY = prediction.letterbox.y + min(
                prediction.letterbox.height - 1,
                Int(localY * Double(prediction.letterbox.height) / region.height)
            )
            for column in firstColumn...finalColumn {
                let sourceX = min(sourceWidth - 1, column * cellSize + cellSize / 2)
                guard Double(sourceX) >= region.minX, Double(sourceX) < region.maxX else { continue }
                let localX = Double(sourceX) - region.minX
                let modelX = prediction.letterbox.x + min(
                    prediction.letterbox.width - 1,
                    Int(localX * Double(prediction.letterbox.width) / region.width)
                )
                let gridIndex = row * columns + column
                probabilities[gridIndex] += prediction.blockedProbabilities[modelY * inputSize + modelX] * weight
                weights[gridIndex] += weight
            }
        }
    }

}
