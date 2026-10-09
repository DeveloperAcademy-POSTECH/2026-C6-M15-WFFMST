import Foundation

public struct FloorPlanCell: Equatable, Sendable {
    public let column: Int
    public let row: Int
    public let index: Int
}

/// Not Codable and has no public initializer: only the full validation boundary
/// can construct this value. Validation does not confer authentication/ownership.
public struct ValidatedFloorPlan: Sendable {
    public let reference: FloorPlanReference
    public let manifest: FloorPlanManifest
    public let files: FloorPlanFiles
    public let pixelsPerMeter: Double
    public var imagePNG: Data { files.imagePNG }
    public var resolvedMask: Data { files.resolvedMask }
    public var metersPerCell: Double { Double(manifest.navigationGrid.cellSizePixels) / pixelsPerMeter }

    fileprivate init(reference: FloorPlanReference, manifest: FloorPlanManifest,
                     files: FloorPlanFiles, pixelsPerMeter: Double) {
        self.reference = reference; self.manifest = manifest; self.files = files
        self.pixelsPerMeter = pixelsPerMeter
    }

    public func cell(at point: ImagePoint) -> FloorPlanCell? {
        guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
              point.x < Double(manifest.imageWidth), point.y < Double(manifest.imageHeight) else { return nil }
        let size = Double(manifest.navigationGrid.cellSizePixels)
        let column = Int(floor(point.x / size)), row = Int(floor(point.y / size))
        return FloorPlanCell(column: column, row: row, index: row * manifest.navigationGrid.columns + column)
    }

    /// Point lookup only. Does not establish route/segment validity or real-world safety.
    public func isBlocked(at point: ImagePoint) -> Bool {
        guard let cell = cell(at: point) else { return true }
        return files.resolvedMask[files.resolvedMask.startIndex + cell.index] == 1
    }

    public func validateStart(at point: ImagePoint) throws {
        guard cell(at: point) != nil else { throw FloorPlanValidationError.invalidCoordinate }
        guard !isBlocked(at: point) else { throw FloorPlanValidationError.blockedStart }
    }
}

public struct FloorPlanValidator: Sendable {
    private let imageValidator: any FloorPlanImageValidating

    /// Requires a trusted decoder implementation, e.g. CQBImageIO's adapter.
    public init(imageValidator: any FloorPlanImageValidating) { self.imageValidator = imageValidator }

    /// CPU work; call off the UI actor. Cancellation is propagated, never mapped
    /// to an input error. No file repairs, re-encoding or network I/O occur here.
    public func validate(files: FloorPlanFiles, reference: FloorPlanReference,
                         expectedReference: FloorPlanReference? = nil) throws -> ValidatedFloorPlan {
        try Task.checkCancellation()
        if let expectedReference, expectedReference != reference { throw FloorPlanValidationError.referenceMismatch }
        guard FloorPlanJSON.isSHA256(reference.navigationSHA256),
              !files.navigationMapJSON.isEmpty,
              files.navigationMapJSON.count <= FloorPlanJSON.maximumManifestBytes else {
            throw FloorPlanValidationError.invalidManifest
        }
        guard FloorPlanJSON.sha256(files.navigationMapJSON) == reference.navigationSHA256 else {
            throw FloorPlanValidationError.integrityMismatch
        }
        let manifest = try FloorPlanJSON.decodeManifest(files.navigationMapJSON)
        guard manifest.floorPlanID == reference.floorPlanID, manifest.revisionID == reference.revisionID else {
            throw FloorPlanValidationError.referenceMismatch
        }
        guard manifest.coordinateSystem == "image-top-left-row-major" else {
            throw FloorPlanValidationError.unsupportedCoordinateSystem(manifest.coordinateSystem)
        }
        try FloorPlanGeometry.validateSize(width: manifest.imageWidth, height: manifest.imageHeight)
        guard manifest.manuallyReviewed,
              FloorPlanJSON.isSHA256(manifest.imageSHA256),
              FloorPlanJSON.isSHA256(manifest.navigationGrid.maskSHA256) else {
            throw FloorPlanValidationError.invalidManifest
        }
        let grid = manifest.navigationGrid
        guard grid.encoding == "uint8-row-major" else { throw FloorPlanValidationError.unsupportedEncoding(grid.encoding) }
        guard (1...4_096).contains(grid.cellSizePixels), (1...4_096).contains(grid.columns),
              (1...4_096).contains(grid.rows), grid.freeValue == 0, grid.blockedValue == 1,
              grid.outsideIsBlocked,
              grid.columns == (manifest.imageWidth + grid.cellSizePixels - 1) / grid.cellSizePixels,
              grid.rows == (manifest.imageHeight + grid.cellSizePixels - 1) / grid.cellSizePixels,
              files.resolvedMask.count == grid.columns * grid.rows else {
            throw FloorPlanValidationError.invalidGrid
        }
        guard !files.imagePNG.isEmpty else { throw FloorPlanValidationError.invalidImage }
        guard FloorPlanJSON.sha256(files.imagePNG) == manifest.imageSHA256,
              FloorPlanJSON.sha256(files.resolvedMask) == grid.maskSHA256 else {
            throw FloorPlanValidationError.integrityMismatch
        }
        try Task.checkCancellation()
        let scale = try FloorPlanGeometry.pixelsPerMeter(for: manifest.scale,
            width: manifest.imageWidth, height: manifest.imageHeight)
        try FloorPlanGeometry.validateOutline(manifest.indoorOutline)
        try validateMask(files.resolvedMask, manifest: manifest)
        try imageValidator.validatePNG(files.imagePNG, width: manifest.imageWidth, height: manifest.imageHeight)
        try Task.checkCancellation()
        return ValidatedFloorPlan(reference: reference, manifest: manifest, files: files, pixelsPerMeter: scale)
    }

    private func validateMask(_ mask: Data, manifest: FloorPlanManifest) throws {
        let grid = manifest.navigationGrid
        for row in 0..<grid.rows {
            try Task.checkCancellation()
            for column in 0..<grid.columns {
                let value = mask[mask.startIndex + row * grid.columns + column]
                guard value <= 1 else { throw FloorPlanValidationError.invalidGrid }
                if value == 1 { continue }
                let x = (Double(column) + 0.5) * Double(grid.cellSizePixels)
                let y = (Double(row) + 0.5) * Double(grid.cellSizePixels)
                let point = NormalizedPoint(x: x / Double(manifest.imageWidth), y: y / Double(manifest.imageHeight))
                guard x < Double(manifest.imageWidth), y < Double(manifest.imageHeight),
                      FloorPlanGeometry.contains(point, polygon: manifest.indoorOutline) else {
                    throw FloorPlanValidationError.invalidGrid
                }
            }
        }
    }
}
