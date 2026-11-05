import CoreGraphics
import CQBCore
import Foundation
import Observation
import OSLog

enum MemberExecutionEnvironment: Sendable, Equatable {
    case operational
    case demo(runID: UUID)
}

/// MemberApp의 화면 흐름과 로컬 녹화 상태를 소유한다.
@MainActor
@Observable
final class MemberStore {
    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "MemberStore")
    @ObservationIgnored let cameraService: ARRecordingService
    @ObservationIgnored private let recordingStarter: any MemberRecordingStarting
    @ObservationIgnored private let executionEnvironment: MemberExecutionEnvironment
    @ObservationIgnored private let recordingFileStore: LocalRecordingFileStore
    @ObservationIgnored private let demoUploadSimulator: MemberDemoUploadSimulator
    @ObservationIgnored private let sessionRepository: any SessionRepository
    @ObservationIgnored private let memberRepository: any MemberRepository
    @ObservationIgnored private let floorPlanFileRepository: any FloorPlanFileRepository
    @ObservationIgnored private let worldMapFileRepository: (any WorldMapFileRepository)?
    @ObservationIgnored private let relocalizationTimeout: Duration
    @ObservationIgnored private var relocalizationTask: Task<Void, Never>?
    @ObservationIgnored private var automaticWorldMap: WorldMapSetup?
    @ObservationIgnored private var cameraSessionIsRunning = false
    private(set) var isSimulatingDemoScan = false
    @ObservationIgnored private var cameraScreenIsVisible = false
    private(set) var positioningState: MemberPositioningState = .manualRequired
    private(set) var isSetupFromCamera = false
    @ObservationIgnored private let recordingRepository: any RecordingRepository
    @ObservationIgnored private let videoChunkRepository: any VideoChunkRepository
    @ObservationIgnored private let trackResultRepository: any TrackResultRepository
    @ObservationIgnored private let soundCandidateRepository: (any SoundCandidateRepository)?
    /// 녹화 중 뽑은 큰 소리 후보(#172). 분석에 실패했거나 데모면 nil이다.
    @ObservationIgnored private var soundCandidateDocument: SoundCandidateDocument?

    private(set) var trainingMap: TrainingMap?
    private(set) var rawTrack: RawTrackDocument?
    private(set) var correction: RouteCorrectionOutput?
    private(set) var recordingCorrectionMode: RouteCorrectionMode?
    private(set) var recordingFiles: LocalRecordingFiles?
    private(set) var savedRecordingURLs: [URL] = []
    private(set) var filesSaved = false
    private(set) var isStarting = false
    private(set) var isJoining = false
    private(set) var isTrackingReady = false
    private(set) var canRetryRecordingStart = false
    @ObservationIgnored private var identity: TrackIdentity?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private let memberID: UUID
    @ObservationIgnored private var sessionObservationTask: Task<Void, Never>?
    @ObservationIgnored private var recordingStartTask: Task<Void, Never>?
    @ObservationIgnored private var recordingStartID: UUID?
    @ObservationIgnored private var readinessHeartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var readinessReportTask: Task<Void, Never>?
    @ObservationIgnored private var shouldReportReadiness = false
    @ObservationIgnored private var reportsReadinessToRepository = true
    @ObservationIgnored private var lastSessionStatus: SessionStatus?
    @ObservationIgnored private var startRequestedBySession = false
    @ObservationIgnored private var hasShownSessionStreamError = false
    @ObservationIgnored private var hasShownReadinessError = false

    private(set) var phase: MemberPhase = .join
    private(set) var pin = ""
    private(set) var memberName = ""
    private(set) var startPoint: CGPoint?
    private(set) var directionPoint: CGPoint?
    private(set) var recordingStartedAt: Date?
    private(set) var errorMessage: String?
    private(set) var uploadProgress = 0.0
    private(set) var isUploadComplete = false
    private(set) var isUploadAbandoned = false
    private(set) var isFinalizingUploadFailure = false
    private(set) var uploadStatusMessage = "업로드를 준비하고 있습니다."
    private(set) var uploadErrorMessage: String?
    private(set) var isUploading = false
    private(set) var uploadedVideoChunkCount = 0
    @ObservationIgnored private var uploadManifest: RecordingUploadManifest?
    @ObservationIgnored private var videoChunkUploadQueue: VideoChunkUploadQueue?
    @ObservationIgnored private var enqueuedVideoChunkIndexes: Set<Int> = []
    @ObservationIgnored private var recordingMetadataStarted = false
    @ObservationIgnored private var recordingMetadataRetryTask: Task<Void, Never>?
    @ObservationIgnored private var recordingMarkedFinishing = false

    init(
        sessionRepository: any SessionRepository,
        memberRepository: any MemberRepository,
        floorPlanFileRepository: any FloorPlanFileRepository,
        recordingRepository: any RecordingRepository,
        videoChunkRepository: any VideoChunkRepository,
        trackResultRepository: any TrackResultRepository,
        soundCandidateRepository: (any SoundCandidateRepository)? = nil,
        worldMapFileRepository: (any WorldMapFileRepository)? = nil,
        relocalizationTimeout: Duration = .seconds(10),
        cameraService: ARRecordingService? = nil,
        recordingStarter: (any MemberRecordingStarting)? = nil,
        executionEnvironment: MemberExecutionEnvironment = .operational,
        demoUploadSimulator: MemberDemoUploadSimulator = MemberDemoUploadSimulator()
    ) {
        self.sessionRepository = sessionRepository
        self.memberRepository = memberRepository
        self.floorPlanFileRepository = floorPlanFileRepository
        self.worldMapFileRepository = worldMapFileRepository
        self.relocalizationTimeout = relocalizationTimeout
        self.recordingRepository = recordingRepository
        self.videoChunkRepository = videoChunkRepository
        self.trackResultRepository = trackResultRepository
        self.soundCandidateRepository = soundCandidateRepository
        let resolvedCamera = cameraService ?? ARRecordingService()
        self.cameraService = resolvedCamera
        self.recordingStarter = recordingStarter ?? resolvedCamera
        self.executionEnvironment = executionEnvironment
        self.demoUploadSimulator = demoUploadSimulator
        switch executionEnvironment {
        case .operational:
            self.recordingFileStore = LocalRecordingFileStore()
        case .demo(let runID):
            self.recordingFileStore = LocalRecordingFileStore(scope: .demo(runID: runID))
        }
        self.memberID = Self.loadOrCreateMemberID()
        self.trainingMap = nil
        resolvedCamera.onSessionRunningChange = { [weak self] running in
            self?.cameraSessionRunningChanged(running)
        }
        resolvedCamera.onTrackingUpdate = { [weak self] pose, normal, ready in
            self?.updatePositioning(pose: pose, isNormal: normal, trackingReady: ready)
        }
    }

    var isDemoMode: Bool {
        if case .demo = executionEnvironment { return true }
        return false
    }

    var isReady: Bool { !isSimulatingDemoScan && startPoint != nil && directionPoint != nil && isTrackingReady }
    var canSetPositionManually: Bool {
        canResetPosition && (positioningState == .manualRequired || positioningState == .manualAvailable
                            || (positioningState == .manualReady && !isReady))
    }
    var canResetPosition: Bool { phase == .waiting && !startRequestedBySession }
    var isWaitingForTrainingStart: Bool { phase == .waiting && startRequestedBySession }
    var canAbandonUpload: Bool {
        !isDemoMode && phase == .uploading && uploadErrorMessage != nil
            && !isUploading && !isFinalizingUploadFailure && !isUploadComplete && !isUploadAbandoned
    }
    var canLeaveUpload: Bool { isUploadComplete || isUploadAbandoned }

    /// 데모 Store에서만 사용한다. 번들 지도를 읽고 서버 참가 요청 없이 로컬 세션을 시작한다.
    func enterDemoSession(session: Session, memberName: String, bundle: Bundle = .main) {
        guard phase == .join, !isJoining else { return }
        isJoining = true
        reportsReadinessToRepository = false
        errorMessage = nil
        trainingMap = nil
        defer { isJoining = false }

        do {
            let map = try BundledTrainingMapLoader.load(bundle: bundle)
            guard map.reference == session.floorPlan else {
                throw SessionFloorPlanLoadFailure()
            }
            sessionID = session.id
            trainingMap = map
            pin = session.pin
            self.memberName = memberName
            lastSessionStatus = session.status
            cameraService.configureWorldMap(nil)
            configurePositioning(setup: nil)
            if isDemoMode {
                isSimulatingDemoScan = true
                positioningState = .relocalizing
            }
            phase = .waiting
            observeSession(id: session.id)
        } catch {
            errorMessage = "데모 도면을 불러오지 못했습니다. 데모를 종료한 뒤 다시 시도해주세요."
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    private(set) var isSimulatedReady = false

    /// Firebase 초기화와 같은 환경 변수 조건을 사용한다. 운영 연결에는 노출하지 않는다.
    var isReadinessTestAvailable: Bool {
        !(ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"] ?? "").isEmpty
    }

    func setSimulatedReadiness(_ isReady: Bool) {
        guard isReadinessTestAvailable, canResetPosition else { return }
        isSimulatedReady = isReady
        scheduleReadinessReport()
    }
    #endif

    /// 테스트는 서버 보고만 대체한다. 실제 AR 준비 판정과 녹화 시작 조건은 바꾸지 않는다.
    private var readinessForReporting: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if isReadinessTestAvailable {
            return isSimulatedReady && startPoint != nil && directionPoint != nil
        }
        #endif
        return isReady
    }

    /// 도면·스캔을 준비하고 대원 등록이 성공한 뒤 위치 설정 방식에 맞춰 화면을 전환한다.
    func join(pin: String, memberName: String) {
        let name = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .join, !isJoining, pin.count == 6,
              pin.allSatisfy({ $0.isASCII && $0.isNumber }), !name.isEmpty else { return }

        isJoining = true
        reportsReadinessToRepository = true
        errorMessage = nil
        trainingMap = nil
        Task { @MainActor in
            defer { isJoining = false }
            do {
                let session = try await sessionRepository.session(forPin: pin)
                let sessionMap: TrainingMap
                do {
                    let files = try await floorPlanFileRepository.download(session.floorPlan)
                    sessionMap = try BundledTrainingMapLoader.load(files: files, for: session.floorPlan)
                } catch {
                    throw SessionFloorPlanLoadFailure()
                }
                let loadedWorldMap: LoadedMemberWorldMap?
                do {
                    if let reference = session.worldMap {
                        guard session.worldMapMatchesFloorPlan, let worldMapFileRepository else {
                            throw RepositoryError.integrityMismatch
                        }
                        let files = try await worldMapFileRepository.download(reference)
                        loadedWorldMap = try await MemberWorldMapLoader.load(files: files, reference: reference)
                    } else { loadedWorldMap = nil }
                } catch is CancellationError {
                    throw CancellationError()
                } catch { throw SessionWorldMapLoadFailure(underlying: error) }
                let member = Member(
                    id: memberID,
                    sessionID: session.id,
                    name: name,
                    isReady: false,
                    lastActiveAt: .now
                )
                try await memberRepository.join(member, pin: pin)

                sessionID = session.id
                trainingMap = sessionMap
                self.pin = pin
                self.memberName = name
                lastSessionStatus = session.status
                cameraService.configureWorldMap(loadedWorldMap, map: sessionMap)
                configurePositioning(setup: loadedWorldMap?.setup)
                phase = loadedWorldMap == nil ? .setup : .waiting
                observeSession(id: session.id)
                startReadinessHeartbeat()
            } catch is CancellationError {
                // 취소된 복원 작업은 참가 실패 안내를 표시하지 않는다.
            } catch let failure as SessionWorldMapLoadFailure {
                errorMessage = Self.worldMapLoadMessage(for: failure.underlying)
            } catch is SessionFloorPlanLoadFailure {
                errorMessage = "이 세션의 도면을 불러오지 못했습니다. 네트워크 연결을 확인하고 다시 시도해주세요."
            } catch let error as RepositoryError {
                switch error {
                case .notFound:
                    errorMessage = "PIN을 확인해주세요."
                case .sessionClosed:
                    errorMessage = "이미 시작했거나 종료된 훈련에는 참가할 수 없습니다."
                default:
                    errorMessage = "세션에 참가하지 못했습니다. 잠시 후 다시 시도해주세요."
                }
            } catch {
                errorMessage = "세션에 참가하지 못했습니다. 네트워크 연결을 확인해주세요."
            }
        }
    }

    private struct SessionWorldMapLoadFailure: Error {
        let underlying: Error
    }

    private static func worldMapLoadMessage(for error: Error) -> String {
        if let loadError = error as? MemberWorldMapLoadError { return loadError.localizedDescription }
        switch error as? RepositoryError {
        case .integrityMismatch:
            return "이 세션의 공간 정보가 손상되었거나 도면과 일치하지 않습니다. 교관에게 공간 스캔을 확인해 달라고 요청해주세요."
        case .fileTooLarge:
            return "이 세션의 공간 정보가 허용 용량을 초과했습니다. 교관에게 공간 스캔을 확인해 달라고 요청해주세요."
        case .notFound:
            return "이 세션의 공간 정보 파일을 찾을 수 없습니다. 교관에게 공간 스캔을 확인해 달라고 요청해주세요."
        default:
            return "이 세션의 공간 정보를 불러오지 못했습니다. 네트워크 연결을 확인하고 다시 참가해주세요."
        }
    }

    func configurePositioning(setup: WorldMapSetup?) {
        cancelRelocalizationTimer()
        isSimulatingDemoScan = false
        automaticWorldMap = setup
        startPoint = nil
        directionPoint = nil
        isTrackingReady = false
        isSetupFromCamera = false
        positioningState = setup == nil ? .manualRequired : .relocalizing
    }

    /// 데모는 실제 AR 세션과 무관하게 카메라 화면의 활성 시간으로 스캔 흐름을 재현한다.
    func cameraScreenVisibilityChanged(_ visible: Bool) {
        cameraScreenIsVisible = visible
        guard isSimulatingDemoScan, phase == .waiting else { return }
        cancelRelocalizationTimer()
        if visible {
            startRelocalizationTimer()
        } else {
            positioningState = .relocalizing
        }
    }

    func cameraSessionRunningChanged(_ running: Bool) {
        cameraSessionIsRunning = running
        if isSimulatingDemoScan {
            updateTrackingReadiness(false)
            return
        }
        cancelRelocalizationTimer()
        updateTrackingReadiness(false)
        guard automaticWorldMap != nil, phase == .waiting else { return }
        startPoint = nil
        directionPoint = nil
        positioningState = .relocalizing
        if running { startRelocalizationTimer() }
    }

    func updatePositioning(pose: ARPose?, isNormal: Bool, trackingReady: Bool) {
        guard phase == .waiting else { return }
        if isSimulatingDemoScan {
            updateTrackingReadiness(false)
            return
        }
        if let worldMap = automaticWorldMap, let map = trainingMap {
            if isNormal, let pose,
               let position = WorldMapPositionCalculator.position(pose: pose, alignment: worldMap.alignment, map: map) {
                cancelRelocalizationTimer()
                startPoint = position.start
                directionPoint = position.direction
                positioningState = trackingReady ? .automaticReady : .relocalizing
            } else {
                startPoint = nil
                directionPoint = nil
                if positioningState != .manualAvailable { positioningState = .relocalizing }
                if cameraSessionIsRunning { startRelocalizationTimer() }
            }
        }
        updateTrackingReadiness(trackingReady && startPoint != nil && directionPoint != nil)
    }

    private func startRelocalizationTimer() {
        guard relocalizationTask == nil, positioningState != .manualAvailable else { return }
        relocalizationTask = Task { @MainActor [weak self, relocalizationTimeout] in
            do { try await Task.sleep(for: relocalizationTimeout) } catch { return }
            guard let self, self.phase == .waiting,
                  (self.isSimulatingDemoScan && self.cameraScreenIsVisible)
                    || (self.automaticWorldMap != nil && self.cameraSessionIsRunning) else { return }
            self.positioningState = .manualAvailable
            self.relocalizationTask = nil
        }
    }

    private func cancelRelocalizationTimer() {
        relocalizationTask?.cancel()
        relocalizationTask = nil
    }

    func returnFromPositionSetup() {
        guard phase == .setup, isSetupFromCamera else { return }
        phase = .waiting
        scheduleReadinessReport()
    }

    private static let memberIDDefaultsKey = "com.wffmst.cqb.memberID"

    private static func loadOrCreateMemberID() -> UUID {
        if let value = UserDefaults.standard.string(forKey: memberIDDefaultsKey),
           let memberID = UUID(uuidString: value) {
            return memberID
        }

        let memberID = UUID()
        UserDefaults.standard.set(memberID.uuidString, forKey: memberIDDefaultsKey)
        return memberID
    }

    func confirmPosition(start: CGPoint, direction: CGPoint) {
        guard phase == .setup, !isReady,
              [start.x, start.y, direction.x, direction.y].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              start != direction else { return }
        guard let map = trainingMap else {
            errorMessage = "테스트 도면 파일을 불러올 수 없습니다."
            return
        }
        guard map.navigation.grid.isFree(map.pixel(start)),
              hypot(map.pixel(direction).x - map.pixel(start).x, map.pixel(direction).y - map.pixel(start).y) >= 10 else {
            errorMessage = "도면 내부의 이동 가능한 출발점과 충분히 떨어진 방향 지점을 선택해주세요."
            return
        }
        startPoint = start
        directionPoint = direction
        positioningState = .manualReady
        phase = .waiting
        scheduleReadinessReport()
    }

    func resetPosition() {
        guard canSetPositionManually else { return }
        cancelRelocalizationTimer()
        automaticWorldMap = nil
        isSimulatingDemoScan = false
        cameraService.configureWorldMap(nil)
        isSetupFromCamera = true
        positioningState = .manualRequired
        startPoint = nil
        directionPoint = nil
        isTrackingReady = false
        #if DEBUG && targetEnvironment(simulator)
        isSimulatedReady = false
        #endif
        phase = .setup
        scheduleReadinessReport()
    }

    /// AR 화면에서 전달하는 준비 상태를 서버 보고와 시작 신호 처리에 반영한다.
    func updateTrackingReadiness(_ isReady: Bool) {
        guard isTrackingReady != isReady else { return }
        isTrackingReady = isReady

        if phase == .setup || phase == .waiting {
            scheduleReadinessReport()
        }
        if isReady, startRequestedBySession {
            scheduleRecordingStart()
        }
    }

    private func scheduleRecordingStart() {
        guard phase == .waiting, recordingStartTask == nil, isReady,
              startRequestedBySession, let sessionID else { return }
        let attemptID = UUID()
        recordingStartID = attemptID
        isStarting = true
        recordingStartTask = Task { @MainActor [weak self] in
            await self?.startRecordingFromSessionSignal(attemptID: attemptID, sessionID: sessionID)
        }
    }

    private func cancelRecordingStart() {
        recordingStartTask?.cancel()
        // Keep task ownership until cleanup finishes, preventing two starts on one recorder.
        isStarting = false
        canRetryRecordingStart = false
    }

    private func isCurrentRecordingStart(_ attemptID: UUID, sessionID: UUID) -> Bool {
        !Task.isCancelled && recordingStartID == attemptID && self.sessionID == sessionID
            && phase == .waiting && startRequestedBySession
    }

    private func startRecordingFromSessionSignal(attemptID: UUID, sessionID: UUID) async {
        defer {
            if recordingStartID == attemptID {
                recordingStartID = nil
                recordingStartTask = nil
                isStarting = false
                // A new session may have requested a start while the cancelled attempt drained.
                if Task.isCancelled { scheduleRecordingStart() }
            }
        }
        guard isCurrentRecordingStart(attemptID, sessionID: sessionID), let map = trainingMap,
              isReady, let startPoint, let directionPoint else { return }
        let correctionMode: RouteCorrectionMode = positioningState == .automaticReady ? .worldMap : .manual
        canRetryRecordingStart = false
        errorMessage = nil
        var pendingFiles: LocalRecordingFiles?
        do {
            let identity = TrackIdentity(sessionID: sessionID, memberID: memberID, recordingID: UUID())
            let files = try recordingFileStore.makeFiles(recordingID: identity.recordingID)
            pendingFiles = files
            if isDemoMode {
                cameraService.onVideoChunkReady = nil
            } else {
                try startVideoChunkUploadQueue(identity: identity, files: files)
                cameraService.onVideoChunkReady = { [weak self] index, url in
                    Task { @MainActor [weak self] in
                        await self?.enqueueVideoChunk(index: index, url: url)
                    }
                }
            }
            try await recordingStarter.startRecording(to: files.videoChunksDirectory,
                start: map.pixel(startPoint), direction: map.pixel(directionPoint),
                shouldStart: { [weak self] in
                    self?.isCurrentRecordingStart(attemptID, sessionID: sessionID) == true
                })
            guard isCurrentRecordingStart(attemptID, sessionID: sessionID) else {
                await recordingStarter.cancelUncommittedRecording()
                videoChunkUploadQueue = nil
                cameraService.onVideoChunkReady = nil
                try? recordingFileStore.discardUncommittedFiles(files)
                return
            }
            if let position = cameraService.recordingPosition {
                self.startPoint = position.start
                self.directionPoint = position.direction
            }
            self.identity = identity
            recordingCorrectionMode = correctionMode
            recordingFiles = files
            savedRecordingURLs = []
            rawTrack = nil
            correction = nil
            soundCandidateDocument = nil
            filesSaved = false
            uploadedVideoChunkCount = 0
            enqueuedVideoChunkIndexes = []
            recordingStartedAt = Date()
            startRequestedBySession = false
            canRetryRecordingStart = false
            phase = .recording
            recordingMetadataStarted = false
            recordingMetadataRetryTask?.cancel()
            recordingMarkedFinishing = false
            if isDemoMode {
                uploadStatusMessage = "데모 영상과 동선을 기기에 기록하고 있습니다."
            } else {
                uploadStatusMessage = "첫 영상 조각을 준비하고 있습니다."
                recordingMetadataRetryTask = Task { @MainActor [weak self] in
                    await self?.startRecordingMetadataWithRetries(identity: identity)
                }
            }
        } catch {
            await recordingStarter.cancelUncommittedRecording()
            videoChunkUploadQueue = nil
            cameraService.onVideoChunkReady = nil
            if let pendingFiles { try? recordingFileStore.discardUncommittedFiles(pendingFiles) }
            guard isCurrentRecordingStart(attemptID, sessionID: sessionID) else { return }
            // Keep the session start request pending so the member can retry while the
            // session is running, or tracking recovery can trigger another attempt.
            canRetryRecordingStart = true
            errorMessage = "녹화 시작에 실패했습니다. 준비 상태를 확인하고 다시 시도해주세요.\n\(error.localizedDescription)"
            if !cameraService.isReady {
                isTrackingReady = false
                scheduleReadinessReport()
            }
        }
    }

    /// Retries the server timestamp write while local recording continues.
    private func startRecordingMetadataWithRetries(identity: TrackIdentity) async {
        for attempt in 1...3 {
            guard !Task.isCancelled, phase == .recording, self.identity == identity else { return }
            do {
                try await recordingRepository.startRecording(
                    Recording(identity: identity, state: .recording, lastActiveAt: .now)
                )
                guard self.identity == identity else { return }
                recordingMetadataStarted = true
                uploadErrorMessage = nil
                return
            } catch {
                recordingMetadataStarted = false
                uploadErrorMessage = error.localizedDescription
                guard attempt < 3, phase == .recording else {
                    uploadStatusMessage = "기록 시작 정보를 서버에 저장하지 못했습니다. 업로드 시 다시 시도합니다."
                    return
                }
                uploadStatusMessage = "기록 시작 정보 전송 실패 · 재시도 중 (\(attempt)/2)"
                do { try await Task.sleep(for: .seconds(attempt)) }
                catch { return }
            }
        }
    }

    /// 녹화 시작 실패 후, running 세션의 시작 요청을 사용해 다시 시도한다.
    func retryStartingRecording() async {
        guard canRetryRecordingStart, startRequestedBySession,
              phase == .waiting, isReady, !isStarting else { return }
        scheduleRecordingStart()
    }

    private func observeSession(id: UUID) {
        sessionObservationTask?.cancel()
        sessionObservationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let updates = self.sessionRepository.observeSession(id: id)
                do {
                    for try await session in updates {
                        guard !Task.isCancelled else { return }
                        await self.receiveSessionStatus(session.status)
                    }
                } catch {
                    if !self.hasShownSessionStreamError {
                        self.errorMessage = "세션 연결이 끊겼습니다. 네트워크 연결을 확인해주세요."
                        self.hasShownSessionStreamError = true
                    }
                }

                guard !Task.isCancelled else { return }
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
    }

    private func receiveSessionStatus(_ status: SessionStatus) async {
        if hasShownSessionStreamError {
            hasShownSessionStreamError = false
            if errorMessage == "세션 연결이 끊겼습니다. 네트워크 연결을 확인해주세요." {
                errorMessage = nil
            }
        }
        guard status != lastSessionStatus else { return }
        lastSessionStatus = status

        switch status {
        case .preparing, .waiting:
            break
        case .running:
            readinessHeartbeatTask?.cancel()
            readinessHeartbeatTask = nil
            guard phase == .waiting, startPoint != nil, directionPoint != nil else {
                leaveSessionWithoutRecording(message: "훈련 시작 전에 준비를 마치지 못해 이 세션에 참가할 수 없습니다.")
                return
            }
            startRequestedBySession = true
            if isReady { scheduleRecordingStart() }
        case .ended:
            readinessHeartbeatTask?.cancel()
            readinessHeartbeatTask = nil
            sessionObservationTask?.cancel()
            sessionObservationTask = nil
            startRequestedBySession = false
            cancelRecordingStart()
            if phase == .recording {
                await finishRecording()
            } else if phase == .setup || phase == .waiting {
                leaveSessionWithoutRecording(message: "훈련이 시작되기 전에 세션이 종료되었습니다.")
            }
        }
    }

    private func startReadinessHeartbeat() {
        readinessHeartbeatTask?.cancel()
        scheduleReadinessReport()
        readinessHeartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                guard let self, self.phase == .setup || self.phase == .waiting else { return }
                self.scheduleReadinessReport()
            }
        }
    }

    /// Coalesces readiness changes so an older network write cannot overwrite a newer state.
    private func scheduleReadinessReport() {
        guard reportsReadinessToRepository else { return }
        shouldReportReadiness = true
        guard readinessReportTask == nil else { return }
        readinessReportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.shouldReportReadiness, !Task.isCancelled {
                self.shouldReportReadiness = false
                guard let sessionID = self.sessionID else { break }
                let member = Member(
                    id: self.memberID,
                    sessionID: sessionID,
                    name: self.memberName,
                    isReady: self.readinessForReporting,
                    lastActiveAt: .now
                )
                do {
                    try await self.memberRepository.updateReadiness(of: member)
                    self.hasShownReadinessError = false
                    if self.errorMessage == "준비 상태를 서버에 전달하지 못했습니다. 연결을 확인해주세요." {
                        self.errorMessage = nil
                    }
                } catch {
                    if !self.hasShownReadinessError {
                        self.errorMessage = "준비 상태를 서버에 전달하지 못했습니다. 연결을 확인해주세요."
                        self.hasShownReadinessError = true
                    }
                }
            }
            self.readinessReportTask = nil
        }
    }

    private func leaveSessionWithoutRecording(message: String) {
        recordingCorrectionMode = nil
        cancelRelocalizationTimer()
        automaticWorldMap = nil
        isSimulatingDemoScan = false
        cameraScreenIsVisible = false
        positioningState = .manualRequired
        isSetupFromCamera = false
        cameraService.configureWorldMap(nil)
        startRequestedBySession = false
        cancelRecordingStart()
        sessionObservationTask?.cancel()
        sessionObservationTask = nil
        readinessHeartbeatTask?.cancel()
        readinessHeartbeatTask = nil
        readinessReportTask?.cancel()
        readinessReportTask = nil
        shouldReportReadiness = false
        cameraService.stop()
        sessionID = nil
        trainingMap = nil
        pin = ""
        memberName = ""
        startPoint = nil
        directionPoint = nil
        isTrackingReady = false
        #if DEBUG && targetEnvironment(simulator)
        isSimulatedReady = false
        #endif
        lastSessionStatus = nil
        startRequestedBySession = false
        canRetryRecordingStart = false
        phase = .join
        errorMessage = message
    }

    func finishRecording() async {
        guard phase == .recording, let map = trainingMap, let identity,
              let startPoint, let directionPoint, let recordingStartedAt else { return }
        phase = .saving
        recordingMetadataRetryTask?.cancel()
        recordingMetadataRetryTask = nil
        errorMessage = cameraService.fatalError
        // 영상 마무리 실패와 동선 저장 실패를 독립적으로 처리한다.
        do {
            savedRecordingURLs = try await cameraService.stopRecording()
            if !isDemoMode {
                for (index, url) in savedRecordingURLs.enumerated() {
                    await enqueueVideoChunk(index: index, url: url)
                }
                try await videoChunkUploadQueue?.setFinalChunkCount(savedRecordingURLs.count)
            }
        }
        catch { errorMessage = error.localizedDescription }
        // 후보는 녹화가 끝날 때 한 번 만든다. 데모는 올리지 않으므로 만들지 않는다.
        if !isDemoMode, let candidates = cameraService.soundCandidates {
            soundCandidateDocument = SoundCandidateDocument(
                identity: identity,
                detector: MemberSoundCandidateRecorder.detector,
                analyzedRanges: candidates.analyzedRanges,
                candidates: candidates.candidates
            )
        }
        rawTrack = RawTrackDocument(identity: identity, floorPlan: map.reference,
            localStartedAt: recordingStartedAt, start: map.pixel(startPoint), direction: map.pixel(directionPoint),
            pixelsPerMeter: cameraService.recordingPixelsPerMeter ?? map.pixelsPerMeter, rotationDegrees: cameraService.rotationDegrees,
            samples: cameraService.samples)
        cameraService.stop()
        await saveAndCorrect()
        if filesSaved, !isDemoMode { startUploading() }
    }

    /// 저장 공간 확보 후 재시도해도 동일한 원본 바이트를 보존한다.
    func retrySaving() async {
        guard phase == .saved, !filesSaved else { return }
        errorMessage = nil
        await saveAndCorrect()
        if filesSaved, !isDemoMode { startUploading() }
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
                let mode = recordingCorrectionMode ?? .manual
                output = await Task.detached(priority: .userInitiated) {
                    RouteCorrectionService.correct(raw: raw, rawHash: hash, map: map, mode: mode)
                }.value
                correction = output
            }
            let soundCandidates = soundCandidateDocument
            try await Task.detached {
                try fileStore.save(output.document, to: files.result)
                if let diagnostics = output.diagnostics {
                    try fileStore.save(diagnostics, to: files.diagnostics)
                }
                // 후보 저장 실패는 동선 저장을 막지 않는다. 메모리의 문서로 업로드는 그대로 시도한다.
                if let soundCandidates {
                    try? fileStore.save(soundCandidates, to: files.soundCandidates)
                }
            }.value
            filesSaved = true
        } catch { errorMessage = "동선 파일 저장 실패: \(error.localizedDescription). 저장 공간을 확보한 뒤 다시 시도해주세요." }
        phase = .saved
    }

    /// 로컬 파일 저장 완료 후 업로드 흐름으로 전환한다.
    func startUploading() {
        guard phase == .saved, filesSaved, !savedRecordingURLs.isEmpty else { return }
        uploadProgress = isDemoMode
            ? 0
            : Double(uploadedVideoChunkCount) / Double(savedRecordingURLs.count + 1)
        isUploadComplete = false
        isUploadAbandoned = false
        if uploadErrorMessage == nil {
            uploadStatusMessage = isDemoMode
                ? "데모 결과를 기기 안에서 확인하고 있습니다."
                : "남은 조각과 보정 결과를 업로드하고 있습니다."
        }
        phase = .uploading
    }

    /// 종료 후 미전송 조각을 재시도하고 보정 결과를 올린 뒤 기록을 완료한다.
    func uploadRecording() async {
        guard phase == .uploading, !isUploading, !isFinalizingUploadFailure,
              !isUploadComplete, !isUploadAbandoned else { return }

        if isDemoMode {
            await completeDemoUpload()
            return
        }

        guard
              let identity,
              let correction, let uploadQueue = videoChunkUploadQueue,
              !savedRecordingURLs.isEmpty else { return }

        isUploading = true
        defer { isUploading = false }

        do {
            if !recordingMetadataStarted {
                try await recordingRepository.startRecording(
                    Recording(identity: identity, state: .recording, lastActiveAt: .now)
                )
                recordingMetadataStarted = true
                uploadErrorMessage = nil
            }
            try await uploadQueue.setFinalChunkCount(savedRecordingURLs.count)
            if !recordingMarkedFinishing {
                try await recordingRepository.updateRecording(
                    Recording(identity: identity, state: .finishing, lastActiveAt: .now,
                              videoChunkCount: savedRecordingURLs.count)
                )
                recordingMarkedFinishing = true
            }

            await uploadQueue.waitForInitialUploads()
            if await uploadQueue.failedChunkCount() > 0 {
                uploadStatusMessage = "실패한 영상 조각을 재시도하고 있습니다."
                try await uploadQueue.retryFailedChunks()
            }
            guard await uploadQueue.failedChunkCount() == 0 else {
                throw UploadError.videoChunkUploadFailed
            }
            uploadManifest = await uploadQueue.currentManifest()
            let totalItems = savedRecordingURLs.count + 1
            refreshUploadProgress(completedItems: savedRecordingURLs.count, totalItems: totalItems)

            if uploadManifest?.uploadedTrackResult != true {
                uploadStatusMessage = "보정 동선 업로드 중"
                try await trackResultRepository.upload(correction.document)
                try await uploadQueue.markTrackResultUploaded()
                uploadManifest = await uploadQueue.currentManifest()
                refreshUploadProgress(completedItems: totalItems, totalItems: totalItems)
            }

            // 음향 후보도 다른 파일처럼 올라가야 done으로 넘긴다. 네트워크·권한 오류나 기록표 저장 실패는
            // 업로드 실패로 남겨 재시도한다(#196). 계약 검증에 걸린 문서는 다시 올려도 실패하므로 로그만 남기고 넘어간다.
            if let soundCandidateDocument, let soundCandidateRepository,
               uploadManifest?.uploadedSoundCandidates != true {
                uploadStatusMessage = "큰 소리 후보 업로드 중"
                do {
                    try await soundCandidateRepository.upload(soundCandidateDocument)
                } catch let error as SoundCandidateValidationError {
                    Self.logger.error("큰 소리 후보가 계약을 지키지 않아 올리지 않음: \(String(describing: error), privacy: .public)")
                }
                try await uploadQueue.markSoundCandidatesUploaded()
                uploadManifest = await uploadQueue.currentManifest()
            }

            uploadStatusMessage = "업로드 완료 확인 중"
            try await recordingRepository.updateRecording(
                Recording(identity: identity, state: .done, lastActiveAt: .now,
                          videoChunkCount: savedRecordingURLs.count)
            )
            uploadProgress = 1
            uploadStatusMessage = "영상과 보정 동선 업로드 완료"
            uploadErrorMessage = nil
            isUploadComplete = true
        } catch {
            uploadErrorMessage = error.localizedDescription
            uploadStatusMessage = "업로드에 실패했습니다. 실패한 항목부터 다시 시도할 수 있습니다."
        }
    }

    private func completeDemoUpload() async {
        guard filesSaved, correction != nil, !savedRecordingURLs.isEmpty else {
            uploadErrorMessage = "데모 결과를 확인할 수 없습니다. 데모를 종료한 뒤 다시 시도해주세요."
            uploadStatusMessage = "데모 처리 실패"
            return
        }

        isUploading = true
        uploadErrorMessage = nil
        await demoUploadSimulator.run { [weak self] step in
            guard let self, self.phase == .uploading else { return }
            self.uploadProgress = step.progress
            self.uploadStatusMessage = step.message
        }
        guard !Task.isCancelled, phase == .uploading, uploadProgress >= 1 else {
            isUploading = false
            return
        }
        isUploadComplete = true
        isUploading = false
    }

    private func startVideoChunkUploadQueue(identity: TrackIdentity, files: LocalRecordingFiles) throws {
        let manifest = RecordingUploadManifest(identity: identity)
        try recordingFileStore.saveUploadManifest(manifest, to: files.uploadManifest)
        uploadManifest = manifest
        videoChunkUploadQueue = VideoChunkUploadQueue(
            repository: videoChunkRepository,
            fileStore: recordingFileStore,
            manifestURL: files.uploadManifest,
            identity: identity,
            manifest: manifest
        ) { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.uploadedVideoChunkCount = status.uploadedCount
                self.uploadErrorMessage = status.latestError
                if status.failedCount > 0 {
                    self.uploadStatusMessage = "영상 조각 \(status.failedCount)개 전송 실패 · 종료 후 재시도합니다."
                } else if let index = status.activeIndex {
                    self.uploadStatusMessage = "영상 조각 \(index + 1) 업로드 중"
                } else {
                    self.uploadStatusMessage = "영상 조각 \(status.uploadedCount)개 업로드 완료"
                }
                let count = self.savedRecordingURLs.count
                if count > 0 {
                    let completed = status.uploadedCount + (self.uploadManifest?.uploadedTrackResult == true ? 1 : 0)
                    self.refreshUploadProgress(completedItems: completed, totalItems: count + 1)
                }
            }
        }
    }

    private func enqueueVideoChunk(index: Int, url: URL) async {
        guard enqueuedVideoChunkIndexes.insert(index).inserted,
              let videoChunkUploadQueue else { return }
        await videoChunkUploadQueue.enqueue(LocalVideoChunk(index: index, url: url))
    }

    private func refreshUploadProgress(completedItems: Int, totalItems: Int) {
        guard totalItems > 0 else { uploadProgress = 1; return }
        uploadProgress = min(max(Double(completedItems) / Double(totalItems), 0), 1)
    }

    func retryUploading() async {
        await uploadRecording()
    }

    /// 재시도를 포기한 기록을 서버 종결 상태로 전환한다. 로컬 파일은 후속 복구를 위해 보존한다.
    func abandonUploading() async {
        guard canAbandonUpload, let identity else { return }
        isFinalizingUploadFailure = true
        defer { isFinalizingUploadFailure = false }
        do {
            try await recordingRepository.updateRecording(
                Recording(
                    identity: identity,
                    state: .failed,
                    lastActiveAt: .now,
                    videoChunkCount: savedRecordingURLs.count
                )
            )
            uploadStatusMessage = "업로드 실패로 기록을 종료했습니다."
            uploadErrorMessage = nil
            isUploadAbandoned = true
        } catch {
            uploadStatusMessage = "업로드 실패 상태를 서버에 전송하지 못했습니다."
            uploadErrorMessage = "연결을 확인한 뒤 업로드 종료를 다시 시도해주세요. \(error.localizedDescription)"
        }
    }

    func clearRecordingError() {
        errorMessage = nil
    }

    /// 화면 구성 해제 시 세션 구독과 카메라를 정리한다. 녹화 중에는 기존 종료 흐름을 먼저 완료해야 한다.
    func shutdown() {
        cancelRelocalizationTimer()
        cameraScreenIsVisible = false
        startRequestedBySession = false
        cancelRecordingStart()
        sessionObservationTask?.cancel()
        sessionObservationTask = nil
        readinessHeartbeatTask?.cancel()
        readinessHeartbeatTask = nil
        readinessReportTask?.cancel()
        readinessReportTask = nil
        recordingMetadataRetryTask?.cancel()
        recordingMetadataRetryTask = nil
        shouldReportReadiness = false
        if phase != .recording {
            cameraService.stop()
            if isDemoMode { try? recordingFileStore.removeDemoRun() }
        }
    }

    func returnToJoin() {
        // 위치 설정 단계에서는 아직 기록이 없으므로 참가 화면으로 복귀할 수 있다.
        guard phase == .setup || (phase == .saved && filesSaved)
                || (phase == .uploading && canLeaveUpload) else { return }
        resetToJoin()
        errorMessage = nil
    }

    /// 완료된 데모 파일만 제거하고 운영 Store로 돌아갈 수 있게 한다.
    func finishDemo() -> Bool {
        guard isDemoMode, phase == .uploading, isUploadComplete, !isUploading else { return false }
        return cleanupDemoAndReset()
    }

    /// 영상 또는 저장 실패로 완료 흐름을 진행할 수 없을 때 데모 파일을 버린다.
    func discardFailedDemo() -> Bool {
        guard isDemoMode, phase == .saved, !isUploading else { return false }
        return cleanupDemoAndReset()
    }

    private func cleanupDemoAndReset() -> Bool {
        do {
            try recordingFileStore.removeDemoRun()
            resetToJoin()
            return true
        } catch {
            errorMessage = "데모 파일을 정리하지 못했습니다. 앱을 다시 실행하면 정리를 다시 시도합니다."
            uploadErrorMessage = error.localizedDescription
            return false
        }
    }

    private func resetToJoin() {
        recordingCorrectionMode = nil
        cancelRelocalizationTimer()
        automaticWorldMap = nil
        isSimulatingDemoScan = false
        cameraScreenIsVisible = false
        positioningState = .manualRequired
        isSetupFromCamera = false
        cameraService.configureWorldMap(nil)
        startRequestedBySession = false
        cancelRecordingStart()
        sessionObservationTask?.cancel()
        sessionObservationTask = nil
        readinessHeartbeatTask?.cancel()
        readinessHeartbeatTask = nil
        readinessReportTask?.cancel()
        readinessReportTask = nil
        recordingMetadataRetryTask?.cancel()
        recordingMetadataRetryTask = nil
        shouldReportReadiness = false
        reportsReadinessToRepository = true
        startRequestedBySession = false
        canRetryRecordingStart = false
        lastSessionStatus = nil
        isTrackingReady = false
        #if DEBUG && targetEnvironment(simulator)
        isSimulatedReady = false
        #endif
        hasShownSessionStreamError = false
        hasShownReadinessError = false
        cameraService.stop()
        cameraService.onVideoChunkReady = nil
        cameraService.discardFinishedCapture()
        identity = nil
        rawTrack = nil
        correction = nil
        soundCandidateDocument = nil
        recordingFiles = nil
        uploadManifest = nil
        savedRecordingURLs = []
        filesSaved = false
        sessionID = nil
        trainingMap = nil
        pin = ""
        memberName = ""
        startPoint = nil
        directionPoint = nil
        recordingStartedAt = nil
        uploadProgress = 0
        isUploadComplete = false
        isUploadAbandoned = false
        isFinalizingUploadFailure = false
        uploadedVideoChunkCount = 0
        enqueuedVideoChunkIndexes = []
        videoChunkUploadQueue = nil
        uploadStatusMessage = "업로드를 준비하고 있습니다."
        uploadErrorMessage = nil
        recordingMetadataStarted = false
        recordingMarkedFinishing = false
        phase = .join
    }

    private enum UploadError: LocalizedError {
        case videoChunkUploadFailed

        var errorDescription: String? {
            switch self {
            case .videoChunkUploadFailed:
                return "일부 영상 조각 업로드에 실패했습니다. 연결을 확인하고 다시 시도해주세요."
            }
        }
    }
}

#if DEBUG
extension MemberStore {
    /// 업로드 실패 종결과 재시도의 경합을 검증하기 위한 최소 상태를 구성한다.
    /// 테스트 타깃에서만 사용하며 실제 사용자 흐름에는 노출하지 않는다.
    func prepareUploadFailureRaceTest(
        identity: TrackIdentity,
        correction: RouteCorrectionOutput,
        files: LocalRecordingFiles,
        chunkURL: URL,
        soundCandidates: SoundCandidateDocument? = nil
    ) async throws {
        self.identity = identity
        self.correction = correction
        soundCandidateDocument = soundCandidates
        recordingFiles = files
        savedRecordingURLs = [chunkURL]
        filesSaved = true
        recordingMetadataStarted = true
        recordingMarkedFinishing = true
        phase = .uploading
        try startVideoChunkUploadQueue(identity: identity, files: files)
        await enqueueVideoChunk(index: 0, url: chunkURL)
        await videoChunkUploadQueue?.waitForInitialUploads()
        await Task.yield()
        uploadErrorMessage = "업로드 실패"
        uploadStatusMessage = "업로드에 실패했습니다."
    }
}
#endif

private struct SessionFloorPlanLoadFailure: Error {}
