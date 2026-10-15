import Foundation

/// 정규화가 끝난 도면 이미지의 픽셀 좌표다.
/// 원점은 왼쪽 위이며, x는 오른쪽, y는 아래쪽으로 증가한다.
public struct ImagePoint: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 이미지 크기에 대한 상대 좌표다. 각 축의 유효 범위는 0...1이다.
public struct NormalizedPoint: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 이미지의 두 지점 사이에서 측정한 실제 거리다.
public struct MapScale: Codable, Hashable, Sendable {
    public let a: ImagePoint
    public let b: ImagePoint
    public let meters: Double

    public init(a: ImagePoint, b: ImagePoint, meters: Double) {
        self.a = a
        self.b = b
        self.meters = meters
    }
}

/// 변경할 수 없는 하나의 도면 파일 묶음을 식별한다.
/// 등록된 도면을 변경하면 revision 대신 새로운 floorPlanID를 생성한다.
public struct FloorPlanReference: Codable, Hashable, Sendable {
    public let floorPlanID: UUID
    public let navigationSHA256: String

    public init(floorPlanID: UUID, navigationSHA256: String) {
        self.floorPlanID = floorPlanID
        self.navigationSHA256 = navigationSHA256
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

    public init(
        columns: Int,
        rows: Int,
        cellSizePixels: Int,
        encoding: String,
        freeValue: UInt8,
        blockedValue: UInt8,
        outsideIsBlocked: Bool,
        maskSHA256: String
    ) {
        self.columns = columns
        self.rows = rows
        self.cellSizePixels = cellSizePixels
        self.encoding = encoding
        self.freeValue = freeValue
        self.blockedValue = blockedValue
        self.outsideIsBlocked = outsideIsBlocked
        self.maskSHA256 = maskSHA256
    }
}

/// 하나의 변경 불가능한 도면 묶음에 대해 navigation-map.json에 저장하는 정보다.
public struct FloorPlanManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let floorPlanID: UUID
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

    public init(
        schemaVersion: Int,
        floorPlanID: UUID,
        coordinateSystem: String,
        imageWidth: Int,
        imageHeight: Int,
        imageSHA256: String,
        scale: MapScale,
        indoorOutline: [NormalizedPoint],
        navigationGrid: NavigationGridDescriptor,
        extractionAlgorithmVersion: String,
        rasterizationVersion: Int,
        manuallyReviewed: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.floorPlanID = floorPlanID
        self.coordinateSystem = coordinateSystem
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageSHA256 = imageSHA256
        self.scale = scale
        self.indoorOutline = indoorOutline
        self.navigationGrid = navigationGrid
        self.extractionAlgorithmVersion = extractionAlgorithmVersion
        self.rasterizationVersion = rasterizationVersion
        self.manuallyReviewed = manuallyReviewed
    }
}

/// 하나의 도면 묶음으로 업로드하는 정확한 파일 바이트다.
public struct FloorPlanFiles: Sendable {
    public let imagePNG: Data
    public let navigationMapJSON: Data
    public let resolvedMask: Data

    public init(imagePNG: Data, navigationMapJSON: Data, resolvedMask: Data) {
        self.imagePNG = imagePNG
        self.navigationMapJSON = navigationMapJSON
        self.resolvedMask = resolvedMask
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
