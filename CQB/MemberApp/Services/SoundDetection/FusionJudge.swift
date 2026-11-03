// 출처: DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST-gunshot-lab
//       Packages/GunshotDetection/Sources/GunshotDetection/FusionJudge.swift @ 713e743a0dc54745a650710156c83601bd837147
// 제품 통합(#172)을 위해 결합 방식에 필요한 파일만 복사했다. 내용은 고치지 않는다.
// 대원 앱의 기본 MainActor 격리를 피하려고 최상위 타입 선언에 nonisolated만 붙였다.
// 감지 로직을 바꿀 때는 연구 저장소에서 먼저 고친 뒤 다시 가져온다.

import Foundation

/// 결합 방식 설정: 급상승 후보 → 내장 분류기 점수 → 잔향 → 중복 묶기.
nonisolated public struct FusionConfig: Sendable {
    /// 분류기 점수로 합산할 내장 분류기(.version1) 라벨
    public var labels: [String]
    /// 결합 판정용 분류기 창 길이와 겹침
    public var windowSeconds: Double
    public var overlapFactor: Double
    public var threshold: Double
    /// 이보다 잔향이 짧으면 폰 근처 충격음으로 보고 거른다. nil이면 잔향 조건을 쓰지 않는다.
    public var minDecaySeconds: Double?
    /// 앞 총성 뒤 이 시간 안의 후보는 같은 총성의 잔향으로 본다. 실탄 더블탭 간격(약 0.51초)보다 짧게 둔다.
    public var debounceSeconds: Double
    /// 후보 시각보다 이만큼 뒤 시점을 담은 창들로 점수를 본다. 총성은 창에 들어온 뒤에야 점수가 오른다.
    public var probeDelaySeconds: Double

    public init(labels: [String] = ["gunshot_gunfire", "artillery_fire"], windowSeconds: Double = 0.5,
                overlapFactor: Double = 0.9, threshold: Double = 0.25, minDecaySeconds: Double? = 0.05,
                debounceSeconds: Double = 0.45, probeDelaySeconds: Double = 0.05) {
        self.labels = labels
        self.windowSeconds = windowSeconds
        self.overlapFactor = overlapFactor
        self.threshold = threshold
        self.minDecaySeconds = minDecaySeconds
        self.debounceSeconds = debounceSeconds
        self.probeDelaySeconds = probeDelaySeconds
    }

    /// 노션 E14에서 고른 값. 잔향 기준은 처음 0.1초였지만 다중 기기 데이터셋에서 기기 5대 중 2대의 실제 총성 감쇠가
    /// 60~85ms라 대부분 걸러져 임시로 0.05초로 낮췄다(methodbench, 2026-10-26). 다음 사격장 녹음으로 다시 확인한다.
    public static let standard = FusionConfig()

    /// 라벨 신뢰도 합(최대 1)
    public func score(_ confidence: (String) -> Double?) -> Double {
        min(1, labels.reduce(0) { $0 + (confidence($1) ?? 0) })
    }
}

/// 분류기 창 하나의 결합 점수. 시각은 OnsetDetector.Candidate와 같은 오디오 시간축(초).
nonisolated public struct ClassifierWindow: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let score: Double

    public init(start: Double, end: Double, score: Double) {
        self.start = start
        self.end = end
        self.score = score
    }
}

nonisolated public enum FusionVerdict: String, Codable, Sendable {
    /// 총성으로 판정
    case accepted
    /// 분류기 점수가 기준 미만
    case lowScore = "low_score"
    /// 잔향이 너무 짧아 폰 근처 충격음으로 봄
    case shortDecay = "short_decay"
    /// 앞 총성 직후(묶기 시간 안)라 같은 총성의 잔향으로 처리
    case duplicate
}

nonisolated public struct FusionDecision: Sendable, Equatable {
    public let candidate: OnsetDetector.Candidate
    /// 후보 직후 시점을 담은 창들의 최고 점수
    public let score: Double
    public let verdict: FusionVerdict
}

/// 급상승 후보와 분류기 창을 받아 결합 판정을 내린다. 앱(실시간)과 GunshotBench(파일)가 같은 코드를 쓴다.
nonisolated public struct FusionJudge: Sendable {
    public let config: FusionConfig
    private var windows: [ClassifierWindow] = []
    private var pending: [OnsetDetector.Candidate] = []
    private var lastAccepted: Double?

    public init(config: FusionConfig = .standard) {
        self.config = config
    }

    /// 후보는 감쇠 측정이 끝난 순서로 오므로 시각 순으로 정렬해 둔다.
    public mutating func add(candidates: [OnsetDetector.Candidate]) {
        guard !candidates.isEmpty else { return }
        pending += candidates
        pending.sort { $0.audioSeconds < $1.audioSeconds }
    }

    /// 창은 시작 시각 순서로 와야 한다. 판정이 끝난 후보를 돌려준다.
    public mutating func add(window: ClassifierWindow) -> [FusionDecision] {
        windows.append(window)
        windows.removeAll { $0.end < window.start - 3 }
        return resolve(latestWindowStart: window.start)
    }

    /// 남은 후보를 지금까지 온 창으로 판정한다(분석 종료 시).
    public mutating func flush() -> [FusionDecision] {
        resolve(latestWindowStart: .infinity)
    }

    /// 파일 분석용: 후보와 창을 한 번에 넣어 판정한다.
    public static func decide(candidates: [OnsetDetector.Candidate], windows: [ClassifierWindow],
                              config: FusionConfig = .standard) -> [FusionDecision] {
        var judge = FusionJudge(config: config)
        judge.add(candidates: candidates)
        var decisions: [FusionDecision] = []
        for w in windows.sorted(by: { $0.start < $1.start }) { decisions += judge.add(window: w) }
        return decisions + judge.flush()
    }

    /// 창은 시작 시각 순서로 도착하므로, 후보 직후 시점(probe)보다 늦게 시작하는 창이 왔으면
    /// probe를 담은 창은 모두 도착한 것이다. 그때 최고 점수로 판정한다.
    private mutating func resolve(latestWindowStart: Double) -> [FusionDecision] {
        var decisions: [FusionDecision] = []
        while let c = pending.first {
            let probe = c.audioSeconds + config.probeDelaySeconds
            guard latestWindowStart > probe else { break }
            pending.removeFirst()
            let score = windows.filter { $0.start <= probe && $0.end >= probe }.map(\.score).max() ?? 0
            let verdict: FusionVerdict
            if score < config.threshold {
                verdict = .lowScore
            } else if let minDecay = config.minDecaySeconds, c.decaySeconds < minDecay {
                verdict = .shortDecay
            } else if let last = lastAccepted, c.audioSeconds - last < config.debounceSeconds {
                verdict = .duplicate
            } else {
                verdict = .accepted
                lastAccepted = c.audioSeconds
            }
            decisions.append(FusionDecision(candidate: c, score: score, verdict: verdict))
        }
        return decisions
    }
}
