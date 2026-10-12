import Foundation
import CQBCore
import CryptoKit
import ImageIO

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
        return try makeMap(imageData: Data(contentsOf: image), navigationData: navigation,
            maskData: mask, imageURL: image, expectedReference: nil)
    }

    /// Builds a map from the immutable file set referenced by a session.
    /// The cache path includes the complete reference so different sessions cannot reuse a stale image.
    static func load(
        files: FloorPlanFiles,
        for reference: FloorPlanReference,
        cacheDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> TrainingMap {
        let validated = try validate(imageData: files.imagePNG, navigationData: files.navigationMapJSON,
            maskData: files.resolvedMask, expectedReference: reference)
        let root = cacheDirectory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SessionFloorPlans", isDirectory: true)
        let directory = root.appendingPathComponent(
            "\(reference.floorPlanID.uuidString)-\(reference.navigationSHA256.lowercased())",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent("original.png")
        try files.imagePNG.write(to: imageURL, options: .atomic)
        return TrainingMap(manifest: validated.manifest, reference: reference,
            navigation: validated.navigation, imageURL: imageURL)
    }

    private static func makeMap(
        imageData: Data,
        navigationData: Data,
        maskData: Data,
        imageURL: URL,
        expectedReference: FloorPlanReference?
    ) throws -> TrainingMap {
        let validated = try validate(imageData: imageData, navigationData: navigationData,
            maskData: maskData, expectedReference: expectedReference)
        let reference = expectedReference ?? FloorPlanReference(
            floorPlanID: validated.manifest.floorPlanID,
            navigationSHA256: sha256(navigationData)
        )
        return TrainingMap(manifest: validated.manifest, reference: reference,
            navigation: validated.navigation, imageURL: imageURL)
    }

    private static func validate(
        imageData: Data,
        navigationData: Data,
        maskData: Data,
        expectedReference: FloorPlanReference?
    ) throws -> (manifest: FloorPlanManifest, navigation: MatchNavigationMap) {
        let manifest = try JSONDecoder().decode(FloorPlanManifest.self, from: navigationData)
        let grid = manifest.navigationGrid
        let (maskCount, maskCountOverflow) = grid.columns.multipliedReportingOverflow(by: grid.rows)
        let (imageWidth, widthOverflow) = grid.columns.multipliedReportingOverflow(by: grid.cellSizePixels)
        let (imageHeight, heightOverflow) = grid.rows.multipliedReportingOverflow(by: grid.cellSizePixels)
        let source = CGImageSourceCreateWithData(imageData as CFData, nil)
        let image = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        let imageType = source.flatMap { CGImageSourceGetType($0) as String? }
        let navigationHash = sha256(navigationData)
        let imageHash = sha256(imageData)
        let maskHash = sha256(maskData)

        guard manifest.schemaVersion == 1,
              manifest.coordinateSystem == "image-pixel-top-left",
              grid.encoding == "uint8-row-major", grid.freeValue == 0, grid.blockedValue == 1,
              grid.outsideIsBlocked,
              grid.columns > 0, grid.rows > 0, grid.cellSizePixels > 0,
              !maskCountOverflow, !widthOverflow, !heightOverflow,
              maskData.count == maskCount, maskData.allSatisfy({ $0 <= 1 }),
              manifest.imageWidth == imageWidth, manifest.imageHeight == imageHeight,
              (1...4096).contains(manifest.imageWidth), (1...4096).contains(manifest.imageHeight),
              manifest.scale.meters.isFinite, manifest.scale.meters > 0,
              manifest.scale.a.x.isFinite, manifest.scale.a.y.isFinite,
              manifest.scale.b.x.isFinite, manifest.scale.b.y.isFinite,
              (0...Double(manifest.imageWidth)).contains(manifest.scale.a.x),
              (0...Double(manifest.imageHeight)).contains(manifest.scale.a.y),
              (0...Double(manifest.imageWidth)).contains(manifest.scale.b.x),
              (0...Double(manifest.imageHeight)).contains(manifest.scale.b.y),
              manifest.scale.a != manifest.scale.b,
              manifest.indoorOutline.count >= 3,
              manifest.indoorOutline.allSatisfy({
                  $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
              }),
              imageType == "public.png", let image,
              image.width == manifest.imageWidth, image.height == manifest.imageHeight,
              imageHash == manifest.imageSHA256.lowercased(),
              maskHash == grid.maskSHA256.lowercased(),
              expectedReference.map({
                  $0.floorPlanID == manifest.floorPlanID &&
                  $0.navigationSHA256.lowercased() == navigationHash
              }) ?? true else {
            throw FloorPlanValidationError.integrityMismatch
        }

        let obstacle = RouteObstacleGrid(columns: grid.columns, rows: grid.rows,
            cellSize: Double(grid.cellSizePixels), blocked: Array(maskData),
            minX: 0, maxX: grid.columns - 1, minY: 0, maxY: grid.rows - 1)
        return (manifest, MatchNavigationMap(grid: obstacle))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
