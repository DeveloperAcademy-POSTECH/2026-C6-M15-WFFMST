import Foundation

/// 대원 기록 상태 보고와 구독.
public protocol RecordingRepository: Sendable {
    /// 대원 앱: 기록을 시작한다. `startedAt`과 `lastActiveAt`을 서버 시각으로 기록한다.
    func startRecording(_ recording: Recording) async throws

    /// 대원 앱: 상태 변경과 생존 신호에 쓴다. `lastActiveAt`을 서버 시각으로 기록한다.
    func updateRecording(_ recording: Recording) async throws

    /// 교관 앱: 세션의 기록 목록이 바뀔 때마다 새 값을 받는다. AAR로 넘어갈지 판단하는 데 쓴다.
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error>
}
