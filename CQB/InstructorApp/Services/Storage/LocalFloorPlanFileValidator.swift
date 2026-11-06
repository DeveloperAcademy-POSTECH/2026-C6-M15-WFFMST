import CQBCore
import Foundation
import ImageIO

nonisolated struct LocalValidatedFloorPlanFiles: Sendable {
    let manifest: FloorPlanManifest
    let grid: LocalObstacleGrid
    let scale: LocalPlanScale
    let outline: [LocalPlanPoint]
    let extractionAlgorithm: LocalWallExtractionAlgorithm
}

/// Storage와 로컬 캐시가 동일한 기준으로 불변 도면 파일 묶음을 검증하게 한다.
nonisolated enum LocalFloorPlanFileValidator {
    static func validate(
        files: FloorPlanFiles,
        reference: FloorPlanReference
    ) throws -> LocalValidatedFloorPlanFiles {
        guard LocalFloorPlanFileBuilder.sha256(files.navigationMapJSON)
                == reference.navigationSHA256.lowercased() else {
            throw RepositoryError.integrityMismatch
        }

        let manifest = try JSONDecoder().decode(FloorPlanManifest.self, from: files.navigationMapJSON)
        guard manifest.schemaVersion == 1,
              manifest.floorPlanID == reference.floorPlanID,
              manifest.coordinateSystem == "image-pixel-top-left",
              manifest.navigationGrid.encoding == "uint8-row-major",
              manifest.navigationGrid.freeValue == 0,
              manifest.navigationGrid.blockedValue == 1,
              manifest.navigationGrid.outsideIsBlocked,
              LocalFloorPlanFileBuilder.sha256(files.imagePNG) == manifest.imageSHA256.lowercased(),
              LocalFloorPlanFileBuilder.sha256(files.resolvedMask)
                == manifest.navigationGrid.maskSHA256.lowercased() else {
            throw RepositoryError.integrityMismatch
        }

        guard let source = CGImageSourceCreateWithData(files.imagePNG as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              (1...4_096).contains(manifest.imageWidth),
              (1...4_096).contains(manifest.imageHeight),
              image.width == manifest.imageWidth,
              image.height == manifest.imageHeight else {
            throw LocalFloorPlanError.invalid("도면 이미지를 복원하지 못했습니다.")
        }

        let descriptor = manifest.navigationGrid
        guard (1...4_096).contains(descriptor.columns),
              (1...4_096).contains(descriptor.rows),
              (1...4_096).contains(descriptor.cellSizePixels),
              descriptor.columns == (manifest.imageWidth + descriptor.cellSizePixels - 1)
                / descriptor.cellSizePixels,
              descriptor.rows == (manifest.imageHeight + descriptor.cellSizePixels - 1)
                / descriptor.cellSizePixels else {
            throw LocalFloorPlanError.invalid("도면 마스크의 크기가 올바르지 않습니다.")
        }
        let (cellCount, overflow) = descriptor.columns.multipliedReportingOverflow(by: descriptor.rows)
        guard !overflow, files.resolvedMask.count == cellCount else {
            throw LocalFloorPlanError.invalid("도면 마스크의 데이터 길이가 올바르지 않습니다.")
        }

        let grid = LocalObstacleGrid(
            columns: descriptor.columns,
            rows: descriptor.rows,
            cellSizePixels: descriptor.cellSizePixels,
            blocked: Array(files.resolvedMask)
        )
        try LocalFloorPlanGeometry.validateGrid(grid)

        let width = Double(manifest.imageWidth)
        let height = Double(manifest.imageHeight)
        let scale = LocalPlanScale(
            a: LocalPlanPoint(x: manifest.scale.a.x / width, y: manifest.scale.a.y / height),
            b: LocalPlanPoint(x: manifest.scale.b.x / width, y: manifest.scale.b.y / height),
            meters: manifest.scale.meters
        )
        _ = try LocalFloorPlanGeometry.validateScale(
            scale,
            width: manifest.imageWidth,
            height: manifest.imageHeight
        )

        let outline = manifest.indoorOutline.map { LocalPlanPoint(x: $0.x, y: $0.y) }
        try LocalFloorPlanGeometry.validateOutline(outline)
        guard let extractionAlgorithm = LocalWallExtractionAlgorithm(
            rawValue: manifest.extractionAlgorithmVersion
        ) else {
            throw LocalFloorPlanError.invalid("지원하지 않는 도면 분석 형식입니다.")
        }

        return LocalValidatedFloorPlanFiles(
            manifest: manifest,
            grid: grid,
            scale: scale,
            outline: outline,
            extractionAlgorithm: extractionAlgorithm
        )
    }
}
