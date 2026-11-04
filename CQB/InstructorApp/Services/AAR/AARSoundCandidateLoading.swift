import CQBCore
import Foundation

/// 기록 하나의 큰 소리 후보를 받는다. 후보가 없거나 분석하지 않은 기록은 빈 배열이다.
nonisolated protocol AARSoundCandidateLoading: Sendable {
    func candidates(for identity: TrackIdentity) async throws -> [AARSoundCandidate]
}

/// 실제 기록용. 후보 저장 계약(#169)이 정해지기 전이라 항상 후보가 없다.
nonisolated struct UnavailableAARSoundCandidateLoader: AARSoundCandidateLoading {
    func candidates(for identity: TrackIdentity) async throws -> [AARSoundCandidate] { [] }
}
