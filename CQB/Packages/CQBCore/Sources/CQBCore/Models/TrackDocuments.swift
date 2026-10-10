import Foundation

/// 한 대원의 기록과 그 기록의 결과·영상 파일을 연결한다.
public struct TrackIdentity: Codable, Hashable, Sendable {
    public let sessionID: UUID
    public let memberID: UUID
    public let recordingID: UUID

    public init(sessionID: UUID, memberID: UUID, recordingID: UUID) {
        self.sessionID = sessionID
        self.memberID = memberID
        self.recordingID = recordingID
    }
}

public enum TrackResultStatus: String, Codable, Sendable {
    case done
    case partial
    case failed
}

/// 점의 생성 출처이며 신뢰도나 정확도를 뜻하지 않는다.
public enum TrackPointProvenance: String, Codable, Sendable {
    case unspecified
    case correctedSample
    case generated
}

public enum TrackUnresolvedReason: String, Codable, Sendable {
    case trackingLost
    case connectionUnverified
    case searchLimit
    case insufficientMovement
    case noCandidate
    case unknown
}

public enum TrackIntervalBounds: String, Codable, Sendable {
    case open = "()"
    case closed = "[]"
    case startOpen = "(]"
    case endOpen = "[)"

    public var includesStart: Bool { self == .closed || self == .endOpen }
    public var includesEnd: Bool { self == .closed || self == .startOpen }
}

public enum TrackResultWarning: String, Codable, Sendable {
    case trackingLost
    case connectionUnverified
    case searchIncomplete
    case headingAmbiguous
}

/// 대원 앱이 로컬에서 사용한 원본 샘플의 양끝을 포함하는 0 기반 범위다.
public struct TrackSampleRange: Codable, Equatable, Sendable {
    public let from: Int
    public let through: Int

    public init(from: Int, through: Int) {
        self.from = from
        self.through = through
    }
}

/// 이 결과 문서 정점의 양끝을 포함하는 범위다.
public struct TrackVertexRange: Codable, Equatable, Sendable {
    public let from: Int
    public let through: Int

    public init(from: Int, through: Int) {
        self.from = from
        self.through = through
    }
}

/// 원본 샘플 범위와 이를 표현하는 결과 정점 범위를 연결한다.
public struct TrackSampleCoverage: Codable, Equatable, Sendable {
    public let samples: TrackSampleRange
    public let vertices: TrackVertexRange?

    public init(samples: TrackSampleRange, vertices: TrackVertexRange?) {
        self.samples = samples
        self.vertices = vertices
    }
}

/// 완전히 보정하지 못한 원본 구간의 진단 정보다.
public struct TrackUnresolvedInterval: Codable, Equatable, Sendable {
    public let from: Double
    public let to: Double
    public let bounds: TrackIntervalBounds
    public let reason: TrackUnresolvedReason
    public let samples: TrackSampleRange
    public let sourceReason: String?

    public init(
        from: Double,
        to: Double,
        bounds: TrackIntervalBounds,
        reason: TrackUnresolvedReason,
        samples: TrackSampleRange,
        sourceReason: String? = nil
    ) {
        self.from = from
        self.to = to
        self.bounds = bounds
        self.reason = reason
        self.samples = samples
        self.sourceReason = sourceReason
    }

    /// 화면 표시용 시간 포함 여부만 판단한다. 원본 샘플은 index로 식별한다.
    public func contains(_ time: Double) -> Bool {
        (time > from || (time == from && bounds.includesStart))
            && (time < to || (time == to && bounds.includesEnd))
    }
}

/// 도면 이미지 픽셀 좌표로 보정된 점이다.
/// `t`는 해당 기록의 시작점을 0초로 한 경과 시간이며 단위는 초다.
public struct TrackResultVertex: Codable, Equatable, Sendable {
    public let t: Double
    public let point: ImagePoint
    public let part: Int
    public let sampleIndex: Int?
    public let provenance: TrackPointProvenance

    public init(
        t: Double,
        point: ImagePoint,
        part: Int,
        sampleIndex: Int?,
        provenance: TrackPointProvenance = .unspecified
    ) {
        self.t = t
        self.point = point
        self.part = part
        self.sampleIndex = sampleIndex
        self.provenance = provenance
    }
}

public struct TrackAlgorithmIdentity: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let settingsID: String

    public init(name: String, version: String, settingsID: String) {
        self.name = name
        self.version = version
        self.settingsID = settingsID
    }
}

/// MVP에서 하나의 기록에 대해 업로드하는 단일 보정 결과다.
public struct TrackResultDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let identity: TrackIdentity
    public let floorPlan: FloorPlanReference
    public let sourceRawSHA256: String
    public let algorithm: TrackAlgorithmIdentity
    public let status: TrackResultStatus
    public let vertices: [TrackResultVertex]
    public let sampleCoverage: [TrackSampleCoverage]
    public let unresolvedIntervals: [TrackUnresolvedInterval]
    public let searchIncomplete: Bool
    public let warnings: [TrackResultWarning]
    public let failureReason: TrackUnresolvedReason?

    public init(
        schemaVersion: Int = 1,
        identity: TrackIdentity,
        floorPlan: FloorPlanReference,
        sourceRawSHA256: String,
        algorithm: TrackAlgorithmIdentity,
        status: TrackResultStatus,
        vertices: [TrackResultVertex],
        sampleCoverage: [TrackSampleCoverage],
        unresolvedIntervals: [TrackUnresolvedInterval],
        searchIncomplete: Bool,
        warnings: [TrackResultWarning],
        failureReason: TrackUnresolvedReason? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.floorPlan = floorPlan
        self.sourceRawSHA256 = sourceRawSHA256
        self.algorithm = algorithm
        self.status = status
        self.vertices = vertices
        self.sampleCoverage = sampleCoverage
        self.unresolvedIntervals = unresolvedIntervals
        self.searchIncomplete = searchIncomplete
        self.warnings = warnings
        self.failureReason = failureReason
    }
}

public enum TrackValidationError: Error, Equatable, Sendable {
    case invalidJSON
    case unsupportedSchema(Int)
    case referenceMismatch
    case rawHashMismatch
    case invalidResult
    case invalidInterval
    case invalidCoverage
    case invalidStatus
    case disconnectedPath
}
