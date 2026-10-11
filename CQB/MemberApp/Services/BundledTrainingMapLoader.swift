import Foundation
import CQBCore

nonisolated struct TrainingMap: Sendable {
    let manifest: FloorPlanManifest
    let reference: FloorPlanReference
    let navigation: MatchNavigationMap
    let imageURL: URL
    var pixelsPerMeter: Double {
        let s = manifest.scale
        return hypot(s.b.x - s.a.x, s.b.y - s.a.y) / s.meters
    }
    func pixel(_ point: CGPoint) -> MapPoint {
        MapPoint(x: point.x * Double(manifest.imageWidth), y: point.y * Double(manifest.imageHeight))
    }
}

nonisolated enum BundledTrainingMapLoader {
    static func load(bundle: Bundle = .main) throws -> TrainingMap {
        func url(_ name: String, _ ext: String) throws -> URL {
            guard let value = bundle.url(forResource: name, withExtension: ext, subdirectory: "TrainingMap")
                ?? bundle.url(forResource: name, withExtension: ext) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return value
        }
        let image = try url("training-map", "pngdata")
        let navigation = try Data(contentsOf: url("training-navigation", "json"))
        let mask = try Data(contentsOf: url("training-mask", "bin"))
        let manifest = try JSONDecoder().decode(FloorPlanManifest.self, from: navigation)
        let grid = manifest.navigationGrid
        guard manifest.schemaVersion == 1, manifest.coordinateSystem == "image-pixel-top-left",
              grid.encoding == "uint8-row-major", grid.freeValue == 0, grid.blockedValue == 1,
              grid.outsideIsBlocked, grid.columns > 0, grid.rows > 0, grid.cellSizePixels > 0,
              mask.count == grid.columns * grid.rows, mask.allSatisfy({ $0 <= 1 }),
              manifest.imageWidth == grid.columns * grid.cellSizePixels,
              manifest.imageHeight == grid.rows * grid.cellSizePixels,
              manifest.scale.meters > 0,
              LocalRecordingFileStore.sha256(mask) == grid.maskSHA256,
              LocalRecordingFileStore.sha256(try Data(contentsOf: image)) == manifest.imageSHA256 else {
            throw FloorPlanValidationError.integrityMismatch
        }
        let obstacle = RouteObstacleGrid(columns: grid.columns, rows: grid.rows,
            cellSize: Double(grid.cellSizePixels), blocked: Array(mask),
            minX: 0, maxX: grid.columns - 1, minY: 0, maxY: grid.rows - 1)
        return TrainingMap(manifest: manifest,
            reference: FloorPlanReference(floorPlanID: manifest.floorPlanID,
                navigationSHA256: LocalRecordingFileStore.sha256(navigation)),
            navigation: MatchNavigationMap(grid: obstacle), imageURL: image)
    }
}
