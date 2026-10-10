import CoreGraphics
import Foundation
import Observation

/// MemberApp의 화면 흐름과 로컬 녹화 상태를 소유한다.
@MainActor
@Observable
final class MemberStore {
    @ObservationIgnored let cameraService: CameraPreviewService
    @ObservationIgnored private let recordingFileStore = LocalRecordingFileStore()

    private(set) var phase: MemberPhase = .join
    private(set) var pin = ""
    private(set) var memberName = ""
    private(set) var startPoint: CGPoint?
    private(set) var directionPoint: CGPoint?
    private(set) var recordingStartedAt: Date?
    private(set) var savedRecordingURL: URL?
    private(set) var recordingError: String?
    private(set) var uploadProgress = 0.0
    private(set) var isUploadComplete = false

    @ObservationIgnored private var isSimulatingUpload = false

    init(cameraService: CameraPreviewService = CameraPreviewService()) {
        self.cameraService = cameraService
    }

    var isReady: Bool { startPoint != nil && directionPoint != nil }

    // TODO: 실제 세션 참가 성공 결과를 받은 뒤 setup으로 전환한다.
    func join(pin: String, memberName: String) {
        let name = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .join, pin.count == 6,
              pin.allSatisfy({ $0.isASCII && $0.isNumber }), !name.isEmpty else { return }
        self.pin = pin
        self.memberName = name
        phase = .setup
    }

    func confirmPosition(start: CGPoint, direction: CGPoint) {
        guard phase == .setup, !isReady,
              [start.x, start.y, direction.x, direction.y].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              start != direction else { return }
        startPoint = start
        directionPoint = direction
        phase = .waiting
    }

    func resetPosition() {
        guard phase == .waiting else { return }
        startPoint = nil
        directionPoint = nil
        phase = .setup
    }

    /// 로컬 목업 제어에서 호출한다. 실제 서버 신호 연결은 후속 작업이다.
    func startRecording() async {
        guard phase == .waiting, isReady else { return }
        recordingError = nil

        do {
            let url = try recordingFileStore.makeRecordingURL()
            try await cameraService.startRecording(to: url)
            savedRecordingURL = url
            recordingStartedAt = Date()
            phase = .recording
        } catch {
            recordingError = error.localizedDescription
        }
    }

    /// 로컬 녹화를 종료하고 파일 기록이 완료된 뒤 저장 완료 화면으로 이동한다.
    func finishRecording() async {
        guard phase == .recording else { return }
        phase = .saving
        recordingError = nil

        do {
            savedRecordingURL = try await cameraService.stopRecording()
            phase = .saved
        } catch {
            recordingError = error.localizedDescription
            recordingStartedAt = nil
            phase = .waiting
        }
    }

    /// 로컬 파일 저장 완료 후 업로드 흐름으로 전환한다.
    func startUploading() {
        guard phase == .saved else { return }
        uploadProgress = 0
        isUploadComplete = false
        phase = .uploading
    }

    /// 임시 업로드: 약 3초 동안 진행한 뒤 저장 완료를 모사한다.
    /// 실제 업로드 연동 시 서비스의 진행률·완료 콜백으로 대체한다.
    func simulateUpload() async {
        guard phase == .uploading, !isUploadComplete, !isSimulatingUpload else { return }
        isSimulatingUpload = true
        defer { isSimulatingUpload = false }

        let clock = ContinuousClock()
        let startedAt = clock.now
        let initialProgress = uploadProgress
        while uploadProgress < 1 {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled, phase == .uploading, !isUploadComplete else { return }
            let elapsed = startedAt.duration(to: clock.now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            updateUploadProgress(initialProgress + seconds / 3)
        }
        guard !Task.isCancelled, phase == .uploading else { return }
        completeUpload()
    }

    func updateUploadProgress(_ progress: Double) {
        guard phase == .uploading, !isUploadComplete, progress.isFinite else { return }
        uploadProgress = min(max(progress, 0), 1)
    }

    // 전송률 100%와 서버 저장 완료 확인은 별개의 이벤트다.
    func completeUpload() {
        guard phase == .uploading else { return }
        uploadProgress = 1
        isUploadComplete = true
    }

    func clearRecordingError() {
        recordingError = nil
    }

    func returnToJoin() {
        guard phase == .saved || (phase == .uploading && isUploadComplete) else { return }
        pin = ""
        memberName = ""
        startPoint = nil
        directionPoint = nil
        recordingStartedAt = nil
        uploadProgress = 0
        isUploadComplete = false
        phase = .join
    }
}
