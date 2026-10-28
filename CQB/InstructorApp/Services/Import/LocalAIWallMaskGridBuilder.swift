import Foundation

/// Core ML의 픽셀별 출력을 기존 2px 장애물 격자로 변환하는 순수 로직입니다.
enum LocalAIWallMaskGridBuilder {
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
