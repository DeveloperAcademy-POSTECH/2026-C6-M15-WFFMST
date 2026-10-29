import Foundation

/// 변경할 수 없는 하나의 훈련장 스캔 묶음을 식별한다.
/// 현장이 바뀌어 다시 스캔하면 새로운 worldMapID를 생성한다.
public struct WorldMapReference: Codable, Hashable, Sendable {
    public let worldMapID: UUID
    /// `setup.json` 바이트의 SHA-256이다.
    public let setupSHA256: String

    public init(worldMapID: UUID, setupSHA256: String) {
        self.worldMapID = worldMapID
        self.setupSHA256 = setupSHA256
    }
}

/// AR 월드 좌표의 자세다. 위치는 미터 단위이고 y는 위쪽이다.
/// 방향은 카메라가 바라보는 쪽을 바닥 평면(x, z)에 투영한 단위 벡터다.
public struct ARPose: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double
    public let forwardX: Double
    public let forwardZ: Double

    public init(x: Double, y: Double, z: Double, forwardX: Double, forwardZ: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.forwardX = forwardX
        self.forwardZ = forwardZ
    }
}

/// 스캔 기준 출발 위치와 도면 위 출발점·방향점이다.
public struct WorldMapStart: Codable, Equatable, Sendable {
    public let pose: ARPose
    public let planPoint: NormalizedPoint
    public let directionPoint: NormalizedPoint

    public init(pose: ARPose, planPoint: NormalizedPoint, directionPoint: NormalizedPoint) {
        self.pose = pose
        self.planPoint = planPoint
        self.directionPoint = directionPoint
    }
}

/// 같은 지점을 도면 좌표와 AR 자세로 기록한 대응점이다.
public struct WorldMapCorrespondence: Codable, Equatable, Sendable {
    public let label: String
    public let planPoint: NormalizedPoint
    public let arPose: ARPose
    public let capturedAt: Date

    public init(label: String, planPoint: NormalizedPoint, arPose: ARPose, capturedAt: Date) {
        self.label = label
        self.planPoint = planPoint
        self.arPose = arPose
        self.capturedAt = capturedAt
    }
}

/// 교관 앱이 대응점으로 한 번 계산한 AR 월드 좌표 → 도면 이미지 좌표 변환이다.
/// 대원 앱은 다시 계산하지 않고 이 값을 그대로 쓴다.
///
/// AR 월드 좌표 `(x, z)`(미터)를 도면 이미지 좌표(픽셀)로 바꾼다. θ = `rotationDegrees`, s = `pixelsPerMeter`.
/// `imageX = translation.x + s * (cos θ * x - sin θ * z)`
/// `imageY = translation.y + s * (sin θ * x + cos θ * z)`
public struct WorldMapAlignment: Codable, Equatable, Sendable {
    public let rotationDegrees: Double
    public let pixelsPerMeter: Double
    /// AR 월드 원점의 도면 이미지 좌표다.
    public let translation: ImagePoint
    /// 대응점에 변환을 적용했을 때의 RMS 오차다. 단위는 미터다.
    public let rmsErrorMeters: Double
    public let algorithmVersion: String

    public init(
        rotationDegrees: Double,
        pixelsPerMeter: Double,
        translation: ImagePoint,
        rmsErrorMeters: Double,
        algorithmVersion: String
    ) {
        self.rotationDegrees = rotationDegrees
        self.pixelsPerMeter = pixelsPerMeter
        self.translation = translation
        self.rmsErrorMeters = rmsErrorMeters
        self.algorithmVersion = algorithmVersion
    }

    /// AR 월드 좌표를 도면 이미지 좌표로 바꾼다.
    public func imagePoint(x: Double, z: Double) -> ImagePoint {
        let radians = rotationDegrees * .pi / 180
        return ImagePoint(
            x: translation.x + pixelsPerMeter * (cos(radians) * x - sin(radians) * z),
            y: translation.y + pixelsPerMeter * (sin(radians) * x + cos(radians) * z)
        )
    }
}

/// `world-map.arexperience`에 적용한 압축이다.
public enum WorldMapCompression: String, Codable, Sendable {
    /// NSKeyedArchiver로 아카이브한 ARWorldMap 바이트 그대로
    case none
    /// 위 바이트를 Apple Compression 프레임워크의 LZFSE로 압축
    case lzfse
}

/// 하나의 스캔 묶음에 대해 setup.json에 저장하는 정보다.
public struct WorldMapSetup: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let worldMapID: UUID
    public let createdAt: Date
    public let floorPlan: FloorPlanReference
    public let start: WorldMapStart
    public let correspondences: [WorldMapCorrespondence]
    public let alignment: WorldMapAlignment
    public let compression: WorldMapCompression
    /// 저장된 `world-map.arexperience` 바이트(압축 후)의 SHA-256이다.
    public let worldMapSHA256: String
    public let worldMapBytes: Int

    public init(
        schemaVersion: Int,
        worldMapID: UUID,
        createdAt: Date,
        floorPlan: FloorPlanReference,
        start: WorldMapStart,
        correspondences: [WorldMapCorrespondence],
        alignment: WorldMapAlignment,
        compression: WorldMapCompression,
        worldMapSHA256: String,
        worldMapBytes: Int
    ) {
        self.schemaVersion = schemaVersion
        self.worldMapID = worldMapID
        self.createdAt = createdAt
        self.floorPlan = floorPlan
        self.start = start
        self.correspondences = correspondences
        self.alignment = alignment
        self.compression = compression
        self.worldMapSHA256 = worldMapSHA256
        self.worldMapBytes = worldMapBytes
    }
}

/// 하나의 스캔 묶음으로 업로드하는 정확한 파일 바이트다.
public struct WorldMapFiles: Sendable {
    public let worldMapArchive: Data
    public let setupJSON: Data

    public init(worldMapArchive: Data, setupJSON: Data) {
        self.worldMapArchive = worldMapArchive
        self.setupJSON = setupJSON
    }
}
