import Foundation

/// 하나의 기록이 거치는 공통 생명주기다.
/// `recording` 상태에서도 완성된 영상 조각을 업로드할 수 있다.
public enum RecordingState: String, Codable, Sendable {
    case recording
    case finishing
    case done
    case failed
}

/// 교관 앱이 AAR 준비 여부를 판단하는 데 필요한 최소 기록 정보다.
public struct Recording: Codable, Sendable, Identifiable {
    public let identity: TrackIdentity
    public let state: RecordingState

    /// 실제 기록을 시작한 서버 기준 시각이다.
    /// `Session.startedAt`과의 차이로 세션 시작 후 기록 시작까지의 시간을 계산한다.
    /// 기록 시작 전이거나 서버 시각이 확정되기 전에는 nil이다.
    public let startedAt: Date?

    /// 기록 중인 대원이 마지막으로 활동을 알린 서버 시각이다.
    /// 구체적인 연결 끊김 판단 시간은 이 모델을 사용하는 쪽에서 결정한다.
    public let lastActiveAt: Date

    /// 녹화가 끝나기 전에는 nil이다.
    /// 조각별 업로드 성공 여부와 재시도 상태는 대원 앱 내부에서 관리한다.
    public let videoChunkCount: Int?

    public var id: UUID { identity.recordingID }

    public init(
        identity: TrackIdentity,
        state: RecordingState,
        startedAt: Date? = nil,
        lastActiveAt: Date,
        videoChunkCount: Int? = nil
    ) {
        self.identity = identity
        self.state = state
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.videoChunkCount = videoChunkCount
    }
}
