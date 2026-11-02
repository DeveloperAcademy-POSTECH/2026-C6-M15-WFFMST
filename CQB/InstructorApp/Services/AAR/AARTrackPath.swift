import CQBCore
import Foundation

/// 보정 결과(`TrackResultDocument`)에서 AAR 타임라인 시각의 대원 위치를 구한다. 동선 선은 그리지 않고 점의 위치만 계산한다.
nonisolated struct AARTrackPath: Equatable, Sendable {
    /// 점을 또렷하게 그릴지, 흐리게 그릴지
    enum Presence: Equatable, Sendable {
        /// 보정된 구간 위
        case tracked
        /// 추적이 끊겼거나 구간이 바뀌는 사이라 마지막으로 알려진 위치에 머무는 중
        case uncertain
    }

    struct Position: Equatable, Sendable {
        let point: ImagePoint
        let presence: Presence
    }

    /// 기록 기준 시각 순서로 정렬한 꼭짓점
    let vertices: [TrackResultVertex]
    let unresolvedIntervals: [TrackUnresolvedInterval]
    /// 세션 시작부터 기록 시작까지의 초. 세션 시각 = 기록 시각 + `recordingOffset`
    let recordingOffset: Double

    init(result: TrackResultDocument, recordingOffset: Double = 0) {
        self.init(
            vertices: result.vertices,
            unresolvedIntervals: result.unresolvedIntervals,
            recordingOffset: recordingOffset
        )
    }

    init(
        vertices: [TrackResultVertex],
        unresolvedIntervals: [TrackUnresolvedInterval] = [],
        recordingOffset: Double = 0
    ) {
        self.vertices = vertices.sorted { $0.t < $1.t }
        self.unresolvedIntervals = unresolvedIntervals
        self.recordingOffset = recordingOffset
    }

    /// 마지막 꼭짓점의 세션 시각. 꼭짓점이 없으면 nil
    var endTime: Double? {
        vertices.last.map { $0.t + recordingOffset }
    }

    /// 세션 시각 `sessionTime`(초)에 점이 있어야 할 위치.
    /// 첫 꼭짓점 이전에는 첫 위치를 흐리게 표시하고, 꼭짓점이 없으면 nil을 반환한다.
    func position(at sessionTime: Double) -> Position? {
        let time = sessionTime - recordingOffset
        guard let first = vertices.first else { return nil }
        guard time >= first.t else {
            return Position(point: first.point, presence: .uncertain)
        }

        let index = lastIndex(atOrBefore: time)
        let current = vertices[index]
        let isUnresolved = unresolvedIntervals.contains { $0.contains(time) }

        guard index + 1 < vertices.count else {
            return Position(point: current.point, presence: isUnresolved ? .uncertain : .tracked)
        }
        let next = vertices[index + 1]
        // 구간(part)이 바뀌는 사이는 잇지 않고 마지막 위치에 머문다.
        guard next.part == current.part else {
            return Position(point: current.point, presence: .uncertain)
        }

        let span = next.t - current.t
        let ratio = span > 0 ? (time - current.t) / span : 0
        let point = ImagePoint(
            x: current.point.x + (next.point.x - current.point.x) * ratio,
            y: current.point.y + (next.point.y - current.point.y) * ratio
        )
        return Position(point: point, presence: isUnresolved ? .uncertain : .tracked)
    }

    /// `t`가 `time` 이하인 마지막 꼭짓점의 위치. 호출 전에 `time >= vertices[0].t`를 확인한다.
    private func lastIndex(atOrBefore time: Double) -> Int {
        var low = 0
        var high = vertices.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if vertices[mid].t <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
