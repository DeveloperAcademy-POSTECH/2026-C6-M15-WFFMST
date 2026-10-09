import Foundation

/// Raw transfer values are not validated merely by constructing or decoding them.
public struct ImagePoint: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct NormalizedPoint: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct MapScale: Codable, Hashable, Sendable {
    public let a: ImagePoint
    public let b: ImagePoint
    public let meters: Double
    public init(a: ImagePoint, b: ImagePoint, meters: Double) {
        self.a = a; self.b = b; self.meters = meters
    }
}

public struct FloorPlanReference: Codable, Hashable, Sendable {
    public let floorPlanID: UUID
    public let revisionID: UUID
    public let navigationSHA256: String

    public init(floorPlanID: UUID, revisionID: UUID, navigationSHA256: String) {
        self.floorPlanID = floorPlanID
        self.revisionID = revisionID
        self.navigationSHA256 = navigationSHA256
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(floorPlanID.uuidString.lowercased(), forKey: .floorPlanID)
        try container.encode(revisionID.uuidString.lowercased(), forKey: .revisionID)
        try container.encode(navigationSHA256, forKey: .navigationSHA256)
    }
}

public struct NavigationGridDescriptor: Codable, Hashable, Sendable {
    public let columns: Int
    public let rows: Int
    public let cellSizePixels: Int
    public let encoding: String
    public let freeValue: UInt8
    public let blockedValue: UInt8
    public let outsideIsBlocked: Bool
    public let maskSHA256: String

    public init(columns: Int, rows: Int, cellSizePixels: Int,
                encoding: String, freeValue: UInt8, blockedValue: UInt8,
                outsideIsBlocked: Bool, maskSHA256: String) {
        self.columns = columns; self.rows = rows; self.cellSizePixels = cellSizePixels
        self.encoding = encoding; self.freeValue = freeValue; self.blockedValue = blockedValue
        self.outsideIsBlocked = outsideIsBlocked; self.maskSHA256 = maskSHA256
    }
}

public struct FloorPlanManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let floorPlanID: UUID
    public let revisionID: UUID
    public let coordinateSystem: String
    public let imageWidth: Int
    public let imageHeight: Int
    public let imageSHA256: String
    public let scale: MapScale
    public let indoorOutline: [NormalizedPoint]
    public let navigationGrid: NavigationGridDescriptor
    public let extractionAlgorithmVersion: String
    public let rasterizationVersion: Int
    public let manuallyReviewed: Bool

    public init(schemaVersion: Int, floorPlanID: UUID, revisionID: UUID,
                coordinateSystem: String, imageWidth: Int, imageHeight: Int,
                imageSHA256: String, scale: MapScale, indoorOutline: [NormalizedPoint],
                navigationGrid: NavigationGridDescriptor, extractionAlgorithmVersion: String,
                rasterizationVersion: Int, manuallyReviewed: Bool) {
        self.schemaVersion = schemaVersion; self.floorPlanID = floorPlanID; self.revisionID = revisionID
        self.coordinateSystem = coordinateSystem; self.imageWidth = imageWidth; self.imageHeight = imageHeight
        self.imageSHA256 = imageSHA256; self.scale = scale; self.indoorOutline = indoorOutline
        self.navigationGrid = navigationGrid; self.extractionAlgorithmVersion = extractionAlgorithmVersion
        self.rasterizationVersion = rasterizationVersion; self.manuallyReviewed = manuallyReviewed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(floorPlanID.uuidString.lowercased(), forKey: .floorPlanID)
        try container.encode(revisionID.uuidString.lowercased(), forKey: .revisionID)
        try container.encode(coordinateSystem, forKey: .coordinateSystem)
        try container.encode(imageWidth, forKey: .imageWidth)
        try container.encode(imageHeight, forKey: .imageHeight)
        try container.encode(imageSHA256, forKey: .imageSHA256)
        try container.encode(scale, forKey: .scale)
        try container.encode(indoorOutline, forKey: .indoorOutline)
        try container.encode(navigationGrid, forKey: .navigationGrid)
        try container.encode(extractionAlgorithmVersion, forKey: .extractionAlgorithmVersion)
        try container.encode(rasterizationVersion, forKey: .rasterizationVersion)
        try container.encode(manuallyReviewed, forKey: .manuallyReviewed)
    }
}

public struct FloorPlanFiles: Sendable {
    public let imagePNG: Data
    public let navigationMapJSON: Data
    public let resolvedMask: Data
    public init(imagePNG: Data, navigationMapJSON: Data, resolvedMask: Data) {
        self.imagePNG = imagePNG; self.navigationMapJSON = navigationMapJSON; self.resolvedMask = resolvedMask
    }
}

public enum FloorPlanValidationError: Error, Equatable, Sendable {
    case invalidManifest
    case invalidImage
    case invalidGrid
    case invalidScale
    case invalidOutline
    case invalidCoordinate
    case blockedStart
    case unsupportedSchema(Int)
    case unsupportedCoordinateSystem(String)
    case unsupportedEncoding(String)
    case integrityMismatch
    case referenceMismatch
}
