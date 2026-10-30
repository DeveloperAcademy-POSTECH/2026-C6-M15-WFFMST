import CoreML
import Foundation

/// Core ML의 픽셀별 출력을 기존 2px 장애물 격자로 변환하는 순수 로직입니다.
enum LocalAIWallMaskGridBuilder {
    /// bottom-origin 모델 결과를 앱의 top-left row-major 격자로 변환합니다.
    nonisolated static func flippingRows(
        _ values: [UInt8],
        columns: Int,
        rows: Int
    ) -> [UInt8] {
        guard columns > 0, rows > 0, values.count == columns * rows else {
            return values
        }
        var result = values
        for row in 0..<(rows / 2) {
            let opposite = rows - 1 - row
            for column in 0..<columns {
                result.swapAt(row * columns + column, opposite * columns + column)
            }
        }
        return result
    }

    /// 이진 Core ML 모델의 NCHW 출력을 타일 결합에 사용할 channel-major 확률 배열로 변환합니다.
    nonisolated static func blockedProbabilities(
        from output: MLMultiArray,
        width: Int,
        height: Int
    ) throws -> [Float] {
        let expectedShape = [1, 1, height, width]
        guard width > 0, height > 0, width <= 4_096, height <= 4_096,
              output.shape.map(\.intValue) == expectedShape,
              output.strides.count == expectedShape.count else {
            throw LocalFloorPlanError.invalid("AI 벽 확률 출력의 크기가 올바르지 않습니다.")
        }
        let strides = output.strides.map(\.intValue)
        let finalRowOffset = (height - 1).multipliedReportingOverflow(by: strides[2])
        let finalColumnOffset = (width - 1).multipliedReportingOverflow(by: strides[3])
        let finalOffset = finalRowOffset.partialValue.addingReportingOverflow(finalColumnOffset.partialValue)
        guard strides.allSatisfy({ $0 >= 0 }),
              !finalRowOffset.overflow, !finalColumnOffset.overflow, !finalOffset.overflow,
              finalOffset.partialValue < output.count else {
            throw LocalFloorPlanError.invalid("AI 벽 확률 출력의 stride가 올바르지 않습니다.")
        }

        func readFloat16(_ offset: Int) -> Float {
            let values = output.dataPointer.bindMemory(to: Float16.self, capacity: output.count)
            return Float(values[offset])
        }
        func readFloat32(_ offset: Int) -> Float {
            let values = output.dataPointer.bindMemory(to: Float.self, capacity: output.count)
            return values[offset]
        }

        let read: (Int) -> Float
        switch output.dataType {
        case .float16:
            read = readFloat16
        case .float32:
            read = readFloat32
        default:
            throw LocalFloorPlanError.invalid("AI 벽 확률 출력은 Float16 또는 Float32여야 합니다.")
        }

        var probabilities = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width {
                let value = read(y * strides[2] + x * strides[3])
                guard value.isFinite, (0...1).contains(value) else {
                    throw LocalFloorPlanError.invalid("AI 벽 확률 출력에 유효하지 않은 값이 있습니다.")
                }
                probabilities[y * width + x] = value
            }
        }
        return probabilities
    }

    /// 8방향으로 연결된 작은 장애물 조각을 제거합니다. 벽 본체와 연결된 픽셀은 보존합니다.
    nonisolated static func removingSmallComponents(
        from blocked: [UInt8],
        columns: Int,
        rows: Int,
        minimumAreaCells: Int
    ) -> [UInt8] {
        guard columns > 0, rows > 0,
              blocked.count == columns * rows,
              blocked.allSatisfy({ $0 <= 1 }),
              minimumAreaCells > 1 else {
            return blocked
        }

        var filtered = blocked
        var visited = [Bool](repeating: false, count: blocked.count)
        for start in blocked.indices where blocked[start] == 1 && !visited[start] {
            var component = [start]
            var cursor = 0
            visited[start] = true
            while cursor < component.count {
                let index = component[cursor]
                cursor += 1
                let column = index % columns
                let row = index / columns
                for offsetY in -1...1 {
                    for offsetX in -1...1 where offsetX != 0 || offsetY != 0 {
                        let neighborColumn = column + offsetX
                        let neighborRow = row + offsetY
                        guard (0..<columns).contains(neighborColumn),
                              (0..<rows).contains(neighborRow) else { continue }
                        let neighbor = neighborRow * columns + neighborColumn
                        guard blocked[neighbor] == 1, !visited[neighbor] else { continue }
                        visited[neighbor] = true
                        component.append(neighbor)
                    }
                }
            }
            if component.count < minimumAreaCells {
                for index in component { filtered[index] = 0 }
            }
        }
        return filtered
    }

    nonisolated static func binaryMask(
        probabilities: [Float],
        width: Int,
        height: Int,
        threshold: Float
    ) throws -> [UInt8] {
        guard width > 0, height > 0, width <= 4_096, height <= 4_096,
              probabilities.count == width * height,
              threshold.isFinite, (0...1).contains(threshold),
              probabilities.allSatisfy(\.isFinite) else {
            throw LocalFloorPlanError.invalid("AI 벽 확률의 크기 또는 값이 올바르지 않습니다.")
        }
        return probabilities.map { $0 >= threshold ? 1 : 0 }
    }

    /// `classLogits`는 Core ML의 NCHW 출력에서 batch를 제거한 channel-major 배열입니다.
    nonisolated static func binaryMask(
        classLogits: [Float],
        classCount: Int,
        width: Int,
        height: Int,
        wallClassIndex: Int
    ) throws -> [UInt8] {
        let pixelCount = width.multipliedReportingOverflow(by: height)
        let valueCount = pixelCount.partialValue.multipliedReportingOverflow(by: classCount)
        guard width > 0, height > 0, width <= 4_096, height <= 4_096,
              classCount > 1, classCount <= 256,
              !pixelCount.overflow, !valueCount.overflow,
              classLogits.count == valueCount.partialValue,
              (0..<classCount).contains(wallClassIndex),
              classLogits.allSatisfy(\.isFinite) else {
            throw LocalFloorPlanError.invalid("AI 클래스 출력의 크기 또는 값이 올바르지 않습니다.")
        }

        var mask = [UInt8](repeating: 0, count: pixelCount.partialValue)
        for pixel in 0..<pixelCount.partialValue {
            var selectedClass = 0
            var selectedLogit = classLogits[pixel]
            for classIndex in 1..<classCount {
                let logit = classLogits[classIndex * pixelCount.partialValue + pixel]
                if logit > selectedLogit {
                    selectedClass = classIndex
                    selectedLogit = logit
                }
            }
            mask[pixel] = selectedClass == wallClassIndex ? 1 : 0
        }
        return mask
    }

    /// Letterbox된 모델 출력의 실제 이미지 영역을 원본 이미지 좌표의 장애물 격자로 복원합니다.
    nonisolated static func grid(
        binaryMask: [UInt8],
        maskWidth: Int,
        maskHeight: Int,
        contentX: Int,
        contentY: Int,
        contentWidth: Int,
        contentHeight: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        cellSizePixels: Int = LocalV13WallDetector.cellSizePixels
    ) throws -> LocalObstacleGrid {
        let maskCount = maskWidth.multipliedReportingOverflow(by: maskHeight)
        guard maskWidth > 0, maskHeight > 0, !maskCount.overflow,
              binaryMask.count == maskCount.partialValue,
              binaryMask.allSatisfy({ $0 <= 1 }),
              sourceWidth > 0, sourceHeight > 0,
              sourceWidth <= 4_096, sourceHeight <= 4_096,
              cellSizePixels > 0,
              sourceWidth.isMultiple(of: cellSizePixels),
              sourceHeight.isMultiple(of: cellSizePixels),
              contentX >= 0, contentY >= 0,
              contentWidth > 0, contentHeight > 0,
              contentX <= maskWidth, contentY <= maskHeight,
              contentWidth <= maskWidth - contentX,
              contentHeight <= maskHeight - contentY else {
            throw LocalFloorPlanError.invalid("AI 벽 마스크의 좌표 또는 크기가 올바르지 않습니다.")
        }

        let columns = sourceWidth / cellSizePixels
        let rows = sourceHeight / cellSizePixels
        var blocked = [UInt8](repeating: 0, count: columns * rows)
        for row in 0..<rows {
            try Task.checkCancellation()
            let sourceY = row * cellSizePixels + cellSizePixels / 2
            let maskY = contentY + min(
                contentHeight - 1,
                sourceY * contentHeight / sourceHeight
            )
            for column in 0..<columns {
                let sourceX = column * cellSizePixels + cellSizePixels / 2
                let maskX = contentX + min(
                    contentWidth - 1,
                    sourceX * contentWidth / sourceWidth
                )
                blocked[row * columns + column] = binaryMask[maskY * maskWidth + maskX]
            }
        }
        return LocalObstacleGrid(
            columns: columns,
            rows: rows,
            cellSizePixels: cellSizePixels,
            blocked: blocked
        )
    }
}
