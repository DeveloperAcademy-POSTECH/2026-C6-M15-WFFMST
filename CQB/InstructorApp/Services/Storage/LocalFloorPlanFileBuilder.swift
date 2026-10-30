import CQBCore
import CryptoKit
import Foundation

nonisolated struct LocalFloorPlanUpload: Sendable {
    let registration: LocalRegisteredFloorPlan
    let files: FloorPlanFiles
    let reference: FloorPlanReference
}

/// 앱 내부 등록 결과를 CQBCore의 기존 Storage 파일 계약으로 변환한다.
nonisolated enum LocalFloorPlanFileBuilder {
    static func build(from registration: LocalRegisteredFloorPlan) throws -> LocalFloorPlanUpload {
        let image = registration.image
        let grid = registration.resolvedGrid
        try LocalFloorPlanGeometry.validateGrid(grid)
        _ = try LocalFloorPlanGeometry.validateScale(
            registration.scale,
            width: image.width,
            height: image.height
        )
        try LocalFloorPlanGeometry.validateOutline(registration.outline)

        guard !image.pngData.isEmpty,
              image.width == grid.columns * grid.cellSizePixels,
              image.height == grid.rows * grid.cellSizePixels else {
            throw LocalFloorPlanError.invalid("도면 이미지와 최종 장애물 격자의 크기가 맞지 않습니다.")
        }

        let mask = Data(grid.blocked)
        let manifest = FloorPlanManifest(
            schemaVersion: 1,
            floorPlanID: registration.id,
            coordinateSystem: "image-pixel-top-left",
            imageWidth: image.width,
            imageHeight: image.height,
            imageSHA256: sha256(image.pngData),
            scale: MapScale(
                a: imagePoint(registration.scale.a, width: image.width, height: image.height),
                b: imagePoint(registration.scale.b, width: image.width, height: image.height),
                meters: registration.scale.meters
            ),
            indoorOutline: registration.outline.map { NormalizedPoint(x: $0.x, y: $0.y) },
            navigationGrid: NavigationGridDescriptor(
                columns: grid.columns,
                rows: grid.rows,
                cellSizePixels: grid.cellSizePixels,
                encoding: "uint8-row-major",
                freeValue: 0,
                blockedValue: 1,
                outsideIsBlocked: true,
                maskSHA256: sha256(mask)
            ),
            extractionAlgorithmVersion: registration.extractionAlgorithm.rawValue,
            rasterizationVersion: 2,
            manuallyReviewed: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let navigationMap = try encoder.encode(manifest)
        let reference = FloorPlanReference(
            floorPlanID: registration.id,
            navigationSHA256: sha256(navigationMap)
        )
        return LocalFloorPlanUpload(
            registration: registration,
            files: FloorPlanFiles(
                imagePNG: image.pngData,
                navigationMapJSON: navigationMap,
                resolvedMask: mask
            ),
            reference: reference
        )
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func imagePoint(_ point: LocalPlanPoint, width: Int, height: Int) -> ImagePoint {
        ImagePoint(x: point.x * Double(width), y: point.y * Double(height))
    }
}
