import Foundation

/// AAR 타임라인(세션 시각)을 대원 영상의 재생 위치로 바꾼다. 영상도 동선처럼 그 대원의 기록 시작이 0초다.
nonisolated struct AARVideoTimeline: Equatable, Sendable {
    enum Frame: Equatable, Sendable {
        /// 이 대원이 아직 녹화를 시작하지 않은 시각
        case notStarted
        /// 영상의 `seconds` 위치
        case playing(seconds: Double)
        /// 영상이 끝난 뒤. 마지막 장면(`seconds`)에 멈춘다
        case ended(seconds: Double)
    }

    /// 세션 시작부터 기록 시작까지의 초
    let recordingOffset: Double
    /// 이어 붙인 영상 전체 길이(초)
    let duration: Double

    /// 영상이 끝나는 세션 시각
    var endTime: Double { recordingOffset + duration }

    func frame(at sessionTime: Double) -> Frame {
        let seconds = sessionTime - recordingOffset
        if seconds < 0 { return .notStarted }
        if seconds >= duration { return .ended(seconds: max(duration, 0)) }
        return .playing(seconds: seconds)
    }
}
