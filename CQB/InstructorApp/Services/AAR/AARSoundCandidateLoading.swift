import CQBCore
import Foundation

/// 기록 하나의 큰 소리 후보를 받는다. 후보가 없거나 분석하지 않은 기록은 빈 배열이다.
nonisolated protocol AARSoundCandidateLoading: Sendable {
    func candidates(for identity: TrackIdentity) async throws -> [AARSoundCandidate]
}

/// 미리보기·테스트용. 항상 후보가 없다.
nonisolated struct UnavailableAARSoundCandidateLoader: AARSoundCandidateLoading {
    func candidates(for identity: TrackIdentity) async throws -> [AARSoundCandidate] { [] }
}

/// 실제 기록용. 대원 앱이 올린 `sound-candidates.json`(#169)을 받아 총성으로 볼 후보만 돌려준다(#192).
nonisolated struct RepositoryAARSoundCandidateLoader: AARSoundCandidateLoading {
    let repository: any SoundCandidateRepository
    var judge: AARSoundCandidateJudge = .standard

    /// 파일이 없거나(분석 전 앱, 업로드 실패) 모르는 버전이면 "분석 안 됨"으로 보고 빈 배열이다.
    /// 그 밖의 오류(네트워크·권한, 다른 기록의 문서, 손상된 문서)는 던진다. `AARStore`는 그 대원만 빼고 묶는다.
    func candidates(for identity: TrackIdentity) async throws -> [AARSoundCandidate] {
        let document: SoundCandidateDocument
        do {
            document = try await repository.download(identity)
        } catch RepositoryError.notFound {
            return []
        } catch SoundCandidateValidationError.unsupportedSchema {
            return []
        }
        return judge.accepted(document.candidates).map { AARSoundCandidate(recordingTime: $0.time) }
    }
}
