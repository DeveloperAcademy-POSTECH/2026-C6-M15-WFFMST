import CQBCore
import Foundation

/// 대원 앱이 넉넉히 올린 큰 소리 후보 중 총성으로 볼 것만 고른다(#192).
/// 기준은 gunshot-lab `713e743`의 결합 방식(`FusionConfig.standard`)과 같다. 사격장 녹음으로 다시 조정한다.
nonisolated struct AARSoundCandidateJudge: Equatable, Sendable {
    /// 점수에 더하는 분류기 라벨
    var labels: [String]
    /// 이보다 점수가 낮으면 총성이 아니다
    var minimumScore: Double
    /// 이보다 잔향이 짧으면 폰 근처 충격음으로 본다. 잔향을 잴 수 없는 후보(`nil`)에는 쓰지 않는다
    var minimumDecaySeconds: Double
    /// 앞에서 고른 총성 뒤 이 시간 안의 후보는 같은 총성의 잔향으로 본다. 실탄 더블탭 간격(약 0.51초)보다 짧다
    var debounceSeconds: Double

    static let standard = AARSoundCandidateJudge(
        labels: ["gunshot_gunfire", "artillery_fire"],
        minimumScore: 0.25,
        minimumDecaySeconds: 0.05,
        debounceSeconds: 0.45
    )

    /// 후보의 분류기 점수. 라벨별 최고 점수를 더하고 1을 넘지 않게 한다.
    /// 연구 코드는 창마다 라벨 점수를 더한 뒤 최고값을 쓰지만, 파일에는 라벨별 최고값만 있다.
    /// 라벨별 최고값의 합은 그보다 같거나 크므로 총성을 놓치는 쪽보다 남기는 쪽으로 기운다.
    func score(of candidate: SoundCandidate) -> Double {
        min(1, labels.reduce(0) { $0 + (candidate.classifierScores[$1] ?? 0) })
    }

    /// 한 기록의 후보에서 총성으로 볼 것만 시각 순으로 돌려준다.
    func accepted(_ candidates: [SoundCandidate]) -> [SoundCandidate] {
        var result: [SoundCandidate] = []
        for candidate in candidates.sorted(by: { $0.time < $1.time }) {
            guard score(of: candidate) >= minimumScore else { continue }
            if let decay = candidate.decaySeconds, decay < minimumDecaySeconds { continue }
            if let last = result.last, candidate.time - last.time < debounceSeconds { continue }
            result.append(candidate)
        }
        return result
    }
}
