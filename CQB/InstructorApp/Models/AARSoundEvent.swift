import Foundation

/// 총성으로 판정한 큰 소리 하나. 시각은 그 대원 기록의 내부 시간(초)이다.
/// 저장 형식은 `SoundCandidateDocument`(#169)이고, 판정은 `AARSoundCandidateJudge`(#192)가 한다.
nonisolated struct AARSoundCandidate: Equatable, Sendable {
    let recordingTime: Double
}

/// AAR 타임라인에 표시하는 큰 소리 이벤트. 시각은 세션 시작부터의 초(재생 위치와 같은 축)다.
nonisolated struct AARSoundEvent: Identifiable, Equatable, Sendable {
    let time: Double
    /// 이 이벤트를 들은 대원. 참가 순서와 무관하게 정렬한다
    let participantIDs: [String]
    /// 최소 기기 수 이상이 함께 들었다
    let isCorroborated: Bool

    var id: Double { time }
}

/// 대원별 후보를 시각이 가까운 것끼리 묶어 이벤트로 만든다.
nonisolated enum AARSoundEventFusion {
    /// 서로 다른 대원의 후보를 같은 소리로 볼 시간 차(초). 임시 값이며 gunshot-lab 결과로 정한다(#168).
    static let defaultMatchWindow = 0.5
    /// 이 수 이상의 대원이 들어야 확인된 이벤트로 본다. 임시 값이며 gunshot-lab 결과로 정한다(#168).
    static let defaultMinimumParticipants = 2

    /// - Parameter candidates: 대원 ID별 후보 시각. 이미 세션 시작부터의 초로 바꾼 값이다
    static func events(
        from candidates: [String: [Double]],
        matchWindow: Double = defaultMatchWindow,
        minimumParticipants: Int = defaultMinimumParticipants
    ) -> [AARSoundEvent] {
        var observations: [Observation] = []
        for (participantID, times) in candidates {
            for time in times {
                observations.append(Observation(time: time, participantID: participantID))
            }
        }
        observations.sort()

        var groups: [[Observation]] = []
        for observation in observations {
            if let first = groups.last?.first, observation.time - first.time <= matchWindow {
                groups[groups.count - 1].append(observation)
            } else {
                groups.append([observation])
            }
        }

        return groups.map { group -> AARSoundEvent in
            let participantIDs = Array(Set(group.map(\.participantID))).sorted()
            return AARSoundEvent(
                time: group.map(\.time).min() ?? 0,
                participantIDs: participantIDs,
                isCorroborated: participantIDs.count >= minimumParticipants
            )
        }
    }

    private struct Observation: Comparable {
        let time: Double
        let participantID: String

        static func < (lhs: Observation, rhs: Observation) -> Bool {
            lhs.time == rhs.time ? lhs.participantID < rhs.participantID : lhs.time < rhs.time
        }
    }
}
