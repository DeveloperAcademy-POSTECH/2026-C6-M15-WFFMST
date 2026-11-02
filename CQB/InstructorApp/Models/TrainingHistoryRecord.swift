import CQBCore
import Foundation

/// 훈련 종료 후 기기에 남기는 지난 훈련 한 건이다.
/// 목록은 이 값만으로 그리고, AAR을 다시 열 때 `sessionID`로 서버 기록을 받는다.
nonisolated struct TrainingHistoryRecord: Identifiable, Equatable, Sendable {
    let sessionID: UUID
    let trainingName: String
    let floorPlan: FloorPlanReference
    /// 도면을 지워도 목록에 이름이 남도록 저장 시점의 이름을 복사한다.
    let floorPlanName: String
    /// 참가 순서대로 저장한다.
    let participantNames: [String]
    let startedAt: Date
    let endedAt: Date

    var id: UUID { sessionID }

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    /// `강유키 등 16명`처럼 첫 대원과 전체 인원을 줄여 보여준다.
    var participantSummary: String {
        guard let first = participantNames.first else { return "참가 대원 없음" }
        guard participantNames.count > 1 else { return first }
        return "\(first) 등 \(participantNames.count)명"
    }
}
