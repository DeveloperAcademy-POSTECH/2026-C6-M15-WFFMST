import CoreGraphics
import CQBCore
import Foundation
import Observation

/// MemberApp의 화면 흐름과 로컬 녹화 상태를 소유한다.
@MainActor
@Observable
final class MemberStore {
    @ObservationIgnored let cameraService: ARRecordingService
    @ObservationIgnored private let recordingFileStore = LocalRecordingFileStore()

    let trainingMap: TrainingMap?
    private(set) var rawTrack: RawTrackDocument?
    private(set) var correction: RouteCorrectionOutput?
    private(set) var recordingFiles: LocalRecordingFiles?
    private(set) var filesSaved = false
    private(set) var isStarting = false
    @ObservationIgnored private var identity: TrackIdentity?
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var memberID = UUID()

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

    init(cameraService: ARRecordingService? = nil) {
        self.cameraService = cameraService ?? ARRecordingService()
        self.trainingMap = try? BundledTrainingMapLoader.load()
    }

    var isReady: Bool { startPoint != nil && directionPoint != nil }

    // TODO: 실제 세션 참가 성공 결과를 받은 뒤 setup으로 전환한다.
    func join(pin: String, memberName: String) {
        let name = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .join, pin.count == 6,
              pin.allSatisfy({ $0.isASCII && $0.isNumber }), !name.isEmpty else { return }
        sessionID = UUID()
        memberID = UUID()
        self.pin = pin
        self.memberName = name
        phase = .setup
    }

    func confirmPosition(start: CGPoint, direction: CGPoint) {
        guard phase == .setup, !isReady,
              [start.x, start.y, direction.x, direction.y].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              start != direction else { return }
        guard let map = trainingMap else {
            recordingError = "테스트 도면 파일을 불러올 수 없습니다."
            return
        }
        guard map.navigation.grid.isFree(map.pixel(start)),
              hypot(map.pixel(direction).x - map.pixel(start).x, map.pixel(direction).y - map.pixel(start).y) >= 10 else {
            recordingError = "도면 내부의 이동 가능한 출발점과 충분히 떨어진 방향 지점을 선택해주세요."
            return
        }
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

    /// 실제 세션/대원 ID를 서버에서 받은 뒤 임시 ID 주입을 교체한다.
    func startRecording() async {
        guard phase == .waiting, !isStarting, let map = trainingMap,
              let startPoint, let directionPoint else { return }
        isStarting = true
        defer { isStarting = false }
        recordingError = nil
        do {
            let identity = TrackIdentity(sessionID: sessionID, memberID: memberID, recordingID: UUID())
            let files = try recordingFileStore.makeFiles(recordingID: identity.recordingID)
            try cameraService.startRecording(to: files.video, start: map.pixel(startPoint), direction: map.pixel(directionPoint))
            self.identity = identity
            recordingFiles = files
            savedRecordingURL = nil
            rawTrack = nil
            correction = nil
            filesSaved = false
            recordingStartedAt = Date()
            phase = .recording
        } catch { recordingError = error.localizedDescription }
    }

    func finishRecording() async {
        guard phase == .recording, let map = trainingMap, let identity,
              let startPoint, let directionPoint, let recordingStartedAt else { return }
        phase = .saving
        recordingError = cameraService.fatalError
        // 영상 마무리 실패와 동선 저장 실패를 독립적으로 처리한다.
        do { savedRecordingURL = try await cameraService.stopRecording() }
        catch { recordingError = error.localizedDescription }
        rawTrack = RawTrackDocument(identity: identity, floorPlan: map.reference,
            localStartedAt: recordingStartedAt, start: map.pixel(startPoint), direction: map.pixel(directionPoint),
            pixelsPerMeter: map.pixelsPerMeter, rotationDegrees: cameraService.rotationDegrees,
            samples: cameraService.samples)
        cameraService.stop()
        await saveAndCorrect()
    }

    /// 저장 공간 확보 후 재시도해도 동일한 원본 바이트를 보존한다.
    func retrySaving() async {
        guard phase == .saved, !filesSaved else { return }
        recordingError = nil
        await saveAndCorrect()
    }

    private func saveAndCorrect() async {
        guard let raw = rawTrack, let files = recordingFiles, let map = trainingMap else { return }
        phase = .saving
        do {
            let fileStore = recordingFileStore
            let hash = try await Task.detached {
                if FileManager.default.fileExists(atPath: files.raw.path) {
                    return LocalRecordingFileStore.sha256(try Data(contentsOf: files.raw))
                }
                return try fileStore.saveRaw(raw, to: files.raw)
            }.value
            phase = .correcting
            let output: RouteCorrectionOutput
            if let correction { output = correction }
            else {
                output = await Task.detached(priority: .userInitiated) {
                    RouteCorrectionService.correct(raw: raw, rawHash: hash, map: map)
                }.value
                correction = output
            }
            try await Task.detached {
                try fileStore.save(output.document, to: files.result)
                if let diagnostics = output.diagnostics {
                    try fileStore.save(diagnostics, to: files.diagnostics)
                }
            }.value
            filesSaved = true
        } catch { recordingError = "동선 파일 저장 실패: \(error.localizedDescription). 저장 공간을 확보한 뒤 다시 시도해주세요." }
        phase = .saved
    }

    /// 로컬 파일 저장 완료 후 업로드 흐름으로 전환한다.
    func startUploading() {
        guard phase == .saved, filesSaved, savedRecordingURL != nil else { return }
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
        guard (phase == .saved && filesSaved) || (phase == .uploading && isUploadComplete) else { return }
        cameraService.discardFinishedCapture()
        identity = nil
        rawTrack = nil
        correction = nil
        recordingFiles = nil
        savedRecordingURL = nil
        filesSaved = false
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
