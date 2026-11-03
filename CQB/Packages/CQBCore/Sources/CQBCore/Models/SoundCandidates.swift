import Foundation

/// 대원 앱이 녹음 중 압축 전 소리로 뽑은 큰 소리 후보. 기록당 하나인 `sound-candidates.json`이다.
/// 최종 판정과 기기 간 합의는 교관 앱이 한다. 계약은 `docs/cqb-core-models.md` "음향 후보"를 따른다.
public struct SoundCandidateDocument: Codable, Equatable, Sendable {
    /// 지금 계약의 버전. 기존 필드의 의미가 바뀔 때만 올린다.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let identity: TrackIdentity
    public let detector: SoundDetectorIdentity
    /// 실제로 소리를 분석한 구간(기록 내부 초). 시작 순이며 겹치지 않는다.
    public let analyzedRanges: [SoundTimeRange]
    /// `time` 오름차순. 모든 후보는 `analyzedRanges` 안에 있다.
    public let candidates: [SoundCandidate]

    public init(
        schemaVersion: Int = SoundCandidateDocument.currentSchemaVersion,
        identity: TrackIdentity,
        detector: SoundDetectorIdentity,
        analyzedRanges: [SoundTimeRange],
        candidates: [SoundCandidate]
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.detector = detector
        self.analyzedRanges = analyzedRanges
        self.candidates = candidates
    }
}

/// 후보를 뽑은 감지 방식. `TrackAlgorithmIdentity`와 같은 역할이다.
public struct SoundDetectorIdentity: Codable, Equatable, Sendable {
    /// 감지 패키지의 방식 이름
    public let name: String
    /// 감지 패키지 버전
    public let version: String
    /// 후보 기준값 묶음의 이름
    public let settingsID: String

    public init(name: String, version: String, settingsID: String) {
        self.name = name
        self.version = version
        self.settingsID = settingsID
    }
}

/// 기록 내부 시간(초) 구간. 0초는 그 기록 영상 조각의 0초와 같다.
public struct SoundTimeRange: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public func contains(_ time: Double) -> Bool {
        start <= time && time <= end
    }
}

/// 큰 소리 후보 하나와 교관 앱이 다시 판정하는 데 쓰는 근거 값.
public struct SoundCandidate: Codable, Equatable, Sendable {
    /// 소리가 급격히 커진 시각(기록 내부 초)
    public let time: Double
    /// 후보 구간의 최고 음량(dBFS, 0 이하)
    public let peakLevelDBFS: Double
    /// 최고점 뒤 소리가 줄어드는 데 걸린 시간(초). 분석 구간 끝에서 잘려 잴 수 없으면 nil
    public let decaySeconds: Double?
    /// 소리 분류기 점수(0~1). 키는 분류기 라벨 그대로다. 모르는 키는 무시한다
    public let classifierScores: [String: Double]

    public init(time: Double, peakLevelDBFS: Double, decaySeconds: Double?, classifierScores: [String: Double]) {
        self.time = time
        self.peakLevelDBFS = peakLevelDBFS
        self.decaySeconds = decaySeconds
        self.classifierScores = classifierScores
    }
}
