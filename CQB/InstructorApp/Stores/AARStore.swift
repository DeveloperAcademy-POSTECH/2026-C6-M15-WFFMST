@preconcurrency import AVFoundation
import CQBCore
import CoreGraphics
import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif

/// AAR 화면의 동선·영상 불러오기와 재생 상태를 관리한다.
/// 훈련 흐름(`InstructorStore`)과 따로 바뀌므로 Store를 분리했다. 화면 전환(`phase`)은 `InstructorStore`가 맡는다.
@MainActor
@Observable
final class AARStore {
    enum TrackState: Equatable {
        case loading
        case ready(AARTrackPath, partial: Bool)
        /// 동선을 표시할 수 없다. 화면에 보여 줄 이유를 담는다
        case unavailable(String)
    }

    enum VideoState {
        case loading
        case ready(AVPlayer, AARVideoTimeline)
        /// 영상을 보여 줄 수 없다. 화면에 보여 줄 이유를 담는다
        case unavailable(String)
    }

    /// 영상 재생 위치가 타임라인과 이만큼(초) 벌어지면 다시 맞춘다
    private static let videoDriftTolerance = 0.3

    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "AARStore")

    @ObservationIgnored private let sessionRepository: any SessionRepository
    @ObservationIgnored private let memberRepository: any MemberRepository
    @ObservationIgnored private let recordingRepository: any RecordingRepository
    @ObservationIgnored private let floorPlanFileRepository: any FloorPlanFileRepository
    @ObservationIgnored private let trackLoader: AARTrackLoader
    @ObservationIgnored private let videoLoader: AARVideoLoader
    @ObservationIgnored private var videoTasks: [String: Task<Void, Never>] = [:]
    /// 영상을 보여 달라고 요청한 대원. 기록 목록을 받기 전에 요청되면 받은 뒤 불러온다
    @ObservationIgnored private var requestedVideoIDs: [String] = []
    /// 참가자 ID별 가장 최근 기록과 세션 시작부터 기록 시작까지의 초
    @ObservationIgnored private var participantRecordings: [String: (recording: Recording, offset: Double)]?
    /// 기록 목록을 받지 못했다. 영상도 받을 수 없다
    @ObservationIgnored private var recordingsLoadFailed = false
    /// 이 세션의 모든 기록. AAR을 마칠 때 영상을 지우는 데 쓴다
    @ObservationIgnored private var sessionRecordings: [Recording] = []
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var loadedSessionID: UUID?

    /// 참가자 ID(`Member.id` 문자열)별 동선 상태
    private(set) var tracks: [String: TrackState] = [:]
    /// 참가자 ID별 영상 상태. 영상 모드에서 선택한 대원만 담긴다
    private(set) var videos: [String: VideoState] = [:]
    private(set) var playbackPosition = 0.0
    private(set) var playbackDuration = 0.0
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var isFloorPlanUnavailable = false
    /// 동선 좌표의 기준이 되는 도면 이미지 크기(픽셀)
    private(set) var floorPlanImageSize: CGSize?
#if canImport(UIKit)
    private(set) var floorPlanImage: UIImage?
#endif

    init(
        sessionRepository: any SessionRepository = DemoSessionRepository(),
        memberRepository: any MemberRepository = DemoMemberRepository(),
        recordingRepository: any RecordingRepository = DemoAARRecordingRepository(),
        trackResultRepository: any TrackResultRepository = DemoTrackResultRepository(),
        floorPlanFileRepository: any FloorPlanFileRepository = DemoFloorPlanFileRepository(),
        videoChunkRepository: any VideoChunkRepository = DemoVideoChunkRepository()
    ) {
        self.sessionRepository = sessionRepository
        self.memberRepository = memberRepository
        self.recordingRepository = recordingRepository
        self.floorPlanFileRepository = floorPlanFileRepository
        trackLoader = AARTrackLoader(repository: trackResultRepository)
        videoLoader = AARVideoLoader(repository: videoChunkRepository)
    }

    var canPlay: Bool { playbackDuration > 0 && !isLoading }

    /// 현재 재생 위치에서 대원 점의 위치. 표시할 위치가 없으면 nil
    func position(for participantID: String) -> AARTrackPath.Position? {
        guard case .ready(let path, _) = tracks[participantID] else { return nil }
        return path.position(at: playbackPosition)
    }

    /// 보정 결과를 받지 못했거나 결과에 꼭짓점이 없어 표시할 좌표가 전혀 없는지 알려준다.
    func hasNoTrackPosition(for participantID: String) -> Bool {
        switch tracks[participantID] {
        case .ready(let path, _): path.vertices.isEmpty
        case .unavailable: true
        case .loading, nil: false
        }
    }

    /// 현재 재생 위치에서 대원 영상의 장면. 영상이 준비되지 않았으면 nil
    func videoFrame(for participantID: String) -> AARVideoTimeline.Frame? {
        guard case .ready(_, let timeline) = videos[participantID] else { return nil }
        return timeline.frame(at: playbackPosition)
    }

    /// 영상 모드에서 보여 줄 대원을 바꾼다. 요금이 내려받기에서 나오므로 요청한 대원만 받는다.
    /// 선택에서 빠진 대원의 영상은 멈추기만 하고 캐시에 둔다.
    func showVideos(for participantIDs: [String]) {
        let previouslyRequestedIDs = Set(requestedVideoIDs)
        requestedVideoIDs = participantIDs
        for (participantID, state) in videos where !participantIDs.contains(participantID) {
            if case .ready(let player, _) = state { player.pause() }
        }
        startRequestedVideoLoads()
        // 기존 영상까지 다시 seek하면 선택·해제할 때 재생 중인 모든 소리가 순간적으로 끊긴다.
        // 캐시에 있어 즉시 표시되는 새 영상은 기본 음소거를 먼저 적용한 뒤 현재 위치로 맞춘다.
        for participantID in participantIDs where !previouslyRequestedIDs.contains(participantID) {
            if case .ready(let player, _) = videos[participantID] {
                player.isMuted = true
            }
            syncVideo(participantID, seek: true)
        }
    }

    /// AAR에 들어갈 때 한 번 부른다. 같은 세션은 다시 받지 않는다.
    /// - Parameter localFloorPlan: 이 기기에 등록된 도면. 세션 도면과 같으면 내려받지 않고 쓴다
    func load(session: Session, participantIDs: [String], localFloorPlan: LocalRegisteredFloorPlan?) async {
        guard loadedSessionID != session.id else { return }
        // 영상 화면이 먼저 요청했을 수 있어 요청한 대원은 남긴다.
        let requested = requestedVideoIDs
        reset()
        requestedVideoIDs = requested
        loadedSessionID = session.id
        isLoading = true
        tracks = Dictionary(uniqueKeysWithValues: participantIDs.map { ($0, TrackState.loading) })
        defer { isLoading = false }

        // 도면과 동선은 서로 기다릴 필요가 없어 함께 받기 시작한다.
        // 세션 시작 시각과 기록 목록은 AAR에 들어갈 때 한 번만 받는다.
        async let floorPlanLoaded: Void = loadFloorPlan(
            session.floorPlan,
            local: localFloorPlan,
            sessionID: session.id
        )
        async let latestSession = Self.first(sessionRepository.observeSession(id: session.id))
        async let recordings = Self.first(recordingRepository.observeRecordings(sessionID: session.id))
        do {
            let (sessionValue, recordingList) = try await (latestSession, recordings)
            if loadedSessionID == session.id {
                rememberRecordings(session: sessionValue ?? session, recordings: recordingList ?? [], participantIDs: participantIDs)
                startRequestedVideoLoads()
                await loadTracks(session: sessionValue ?? session, recordings: recordingList ?? [], participantIDs: participantIDs)
            }
        } catch {
            if loadedSessionID == session.id {
                Self.logger.error("AAR 기록 불러오기 실패: \(error.localizedDescription, privacy: .private)")
                tracks = Dictionary(uniqueKeysWithValues: participantIDs.map { ($0, TrackState.unavailable("기록을 불러오지 못했습니다.")) })
                recordingsLoadFailed = true
                startRequestedVideoLoads()
            }
        }
        await floorPlanLoaded
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func setPlaybackPosition(_ value: Double) {
        guard value.isFinite else { return }
        playbackPosition = min(max(0, value), playbackDuration)
        syncVideos(seek: true)
    }

    /// AAR을 마치고 나갈 때 이 세션의 영상을 Storage와 기기 캐시에서 지운다.
    /// 지금은 영상을 남기기로 해 부르지 않는다(#66).
    /// 삭제가 실패해도 나가는 것을 막지 않는다. 남은 영상은 Storage 수명 주기 규칙이 켜져 있으면 1일 뒤 지워진다.
    func finish() {
        let recordings = sessionRecordings.map { (identity: $0.identity, chunkCount: $0.videoChunkCount) }
        reset()
        guard !recordings.isEmpty else { return }
        let loader = videoLoader
        Task {
            let failed = await loader.finish(recordings)
            if !failed.isEmpty {
                Self.logger.error("AAR 영상 삭제 실패: \(failed.count)개 기록")
            }
        }
    }

    /// 재생을 멈추고 불러온 동선과 영상을 비운다.
    func reset() {
        pause()
        deactivateAudioSession()
        loadedSessionID = nil
        tracks = [:]
        videoTasks.values.forEach { $0.cancel() }
        videoTasks = [:]
        videos = [:]
        requestedVideoIDs = []
        participantRecordings = nil
        recordingsLoadFailed = false
        sessionRecordings = []
        playbackPosition = 0
        playbackDuration = 0
        isFloorPlanUnavailable = false
        floorPlanImageSize = nil
#if canImport(UIKit)
        floorPlanImage = nil
#endif
        let loader = trackLoader
        Task { await loader.reset() }
    }

    private func play() {
        guard canPlay else { return }
        if playbackPosition >= playbackDuration { playbackPosition = 0 }
        activateAudioSession()
        isPlaying = true
        syncVideos(seek: true)
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                let now = clock.now
                let elapsed = last.duration(to: now)
                last = now
                guard let self, self.isPlaying else { return }
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                self.playbackPosition = min(self.playbackPosition + seconds, self.playbackDuration)
                if self.playbackPosition >= self.playbackDuration {
                    self.isPlaying = false
                    self.syncVideos(seek: false)
                    return
                }
                self.syncVideos(seek: false)
            }
        }
    }

    private func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
        syncVideos(seek: false)
    }

    /// AAR 영상의 소리가 기기 무음 설정과 무관하게 미디어로 재생되도록 한다.
    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            Self.logger.error("AAR 오디오 세션 활성화 실패: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            Self.logger.error("AAR 오디오 세션 비활성화 실패: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// 화면에 보이는 영상을 타임라인 위치에 맞춘다.
    /// - Parameter seek: 사용자가 위치를 옮겼을 때 true. 재생 중에는 많이 벌어졌을 때만 다시 맞춘다
    private func syncVideos(seek: Bool) {
        for participantID in requestedVideoIDs {
            syncVideo(participantID, seek: seek)
        }
    }

    private func syncVideo(_ participantID: String, seek: Bool) {
        guard requestedVideoIDs.contains(participantID),
              case .ready(let player, let timeline) = videos[participantID]
        else { return }

        switch timeline.frame(at: playbackPosition) {
        case .notStarted:
            player.pause()
            Self.seek(player, to: 0, ifDriftFrom: seek ? nil : 0)
        case .playing(let seconds):
            Self.seek(player, to: seconds, ifDriftFrom: seek ? nil : player.currentTime().seconds)
            if isPlaying {
                if player.rate == 0 { player.play() }
            } else {
                player.pause()
            }
        case .ended(let seconds):
            player.pause()
            Self.seek(player, to: seconds, ifDriftFrom: seek ? nil : player.currentTime().seconds)
        }
    }

    /// `current`가 nil이면 항상, 아니면 목표와 많이 벌어졌을 때만 옮긴다.
    private static func seek(_ player: AVPlayer, to seconds: Double, ifDriftFrom current: Double?) {
        if let current, current.isFinite, abs(current - seconds) < videoDriftTolerance { return }
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func rememberRecordings(session: Session, recordings: [Recording], participantIDs: [String]) {
        sessionRecordings = recordings
        var latest: [String: (recording: Recording, offset: Double)] = [:]
        for participantID in participantIDs {
            guard let recording = Self.latestRecording(for: participantID, in: recordings) else { continue }
            latest[participantID] = (recording, Self.recordingOffset(session: session, recording: recording))
        }
        participantRecordings = latest
    }

    /// 요청한 대원 중 아직 받지 않은 영상을 받기 시작한다. 기록 목록을 받기 전이면 받는 중으로만 표시한다.
    /// 받지 못한 영상은 대원을 다시 선택하면 다시 받는다.
    private func startRequestedVideoLoads() {
        for participantID in requestedVideoIDs where videoTasks[participantID] == nil {
            if case .ready = videos[participantID] { continue }
            if recordingsLoadFailed {
                videos[participantID] = .unavailable("기록을 불러오지 못했습니다.")
                continue
            }
            guard let participantRecordings else {
                videos[participantID] = .loading
                continue
            }
            guard let entry = participantRecordings[participantID] else {
                videos[participantID] = .unavailable("기록이 없습니다.")
                continue
            }
            videos[participantID] = .loading
            let sessionID = loadedSessionID
            let loader = videoLoader
            videoTasks[participantID] = Task { [weak self] in
                let result = await loader.load(entry.recording.identity, chunkCount: entry.recording.videoChunkCount)
                let state = await Self.videoState(for: result, offset: entry.offset)
                guard let self, !Task.isCancelled, self.loadedSessionID == sessionID else { return }
                self.videoTasks[participantID] = nil
                self.videos[participantID] = state
                self.updatePlaybackDuration()
                // 새로 준비된 영상만 맞추고 이미 재생 중인 다른 영상은 건드리지 않는다.
                self.syncVideo(participantID, seek: true)
            }
        }
    }

    private static func videoState(for result: AARVideoLoadResult, offset: Double) async -> VideoState {
        switch result {
        case .loaded(let chunks):
            do {
                let composition = try await AARVideoComposer.compose(chunks)
                let duration = try await composition.load(.duration).seconds
                let player = AVPlayer(playerItem: AVPlayerItem(asset: composition))
                player.isMuted = true
                player.actionAtItemEnd = .pause
                return .ready(player, AARVideoTimeline(recordingOffset: offset, duration: duration.isFinite ? duration : 0))
            } catch {
                logger.error("AAR 영상 이어 붙이기 실패: \(error.localizedDescription, privacy: .private)")
                return .unavailable("영상을 재생할 수 없습니다.")
            }
        case .notUploaded:
            return .unavailable("영상이 아직 올라오지 않았습니다.")
        case .unavailable:
            return .unavailable("영상을 불러오지 못했습니다.")
        }
    }

    /// 동선과 영상 중 가장 늦게 끝나는 시각까지 재생한다.
    private func updatePlaybackDuration() {
        let trackEnds = tracks.values.compactMap { state -> Double? in
            guard case .ready(let path, _) = state else { return nil }
            return path.endTime
        }
        let videoEnds = videos.values.compactMap { state -> Double? in
            guard case .ready(_, let timeline) = state else { return nil }
            return timeline.endTime
        }
        playbackDuration = (trackEnds + videoEnds).max() ?? 0
    }

    private func loadTracks(session: Session, recordings: [Recording], participantIDs: [String]) async {
        let loader = trackLoader
        let floorPlan = session.floorPlan
        let results = await withTaskGroup(of: (String, TrackState).self) { group in
            for participantID in participantIDs {
                guard let recording = Self.latestRecording(for: participantID, in: recordings) else {
                    tracks[participantID] = .unavailable("기록이 없습니다.")
                    continue
                }
                let offset = Self.recordingOffset(session: session, recording: recording)
                group.addTask {
                    let result = await loader.load(recording.identity, floorPlan: floorPlan, recordingOffset: offset)
                    return (participantID, Self.trackState(for: result))
                }
            }
            var states: [(String, TrackState)] = []
            for await state in group { states.append(state) }
            return states
        }
        guard loadedSessionID == session.id else { return }
        for (participantID, state) in results { tracks[participantID] = state }
        updatePlaybackDuration()
    }

    private func loadFloorPlan(
        _ reference: FloorPlanReference,
        local: LocalRegisteredFloorPlan?,
        sessionID: UUID
    ) async {
        if let local, local.id == reference.floorPlanID {
            guard loadedSessionID == sessionID else { return }
            floorPlanImageSize = CGSize(width: local.image.width, height: local.image.height)
#if canImport(UIKit)
            floorPlanImage = UIImage(data: local.image.pngData)
#endif
            return
        }
        // 이 기기에 없는 도면(앱 재설치, 다른 iPad)은 Storage에서 받는다.
        do {
            let files = try await floorPlanFileRepository.download(reference)
            guard loadedSessionID == sessionID else { return }
            let manifest = try JSONDecoder().decode(FloorPlanManifest.self, from: files.navigationMapJSON)
            floorPlanImageSize = CGSize(width: manifest.imageWidth, height: manifest.imageHeight)
#if canImport(UIKit)
            floorPlanImage = UIImage(data: files.imagePNG)
#endif
        } catch {
            guard loadedSessionID == sessionID else { return }
            Self.logger.error("AAR 도면 불러오기 실패: \(error.localizedDescription, privacy: .private)")
            isFloorPlanUnavailable = true
        }
    }

    /// 한 대원에게 기록이 여러 개면 가장 늦게 시작한 기록을 쓴다.
    private static func latestRecording(for participantID: String, in recordings: [Recording]) -> Recording? {
        recordings
            .filter { $0.identity.memberID.uuidString == participantID }
            .max { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    /// 세션 시작부터 기록 시작까지의 초. 둘 중 하나라도 모르면 0으로 둔다.
    private static func recordingOffset(session: Session, recording: Recording) -> Double {
        guard let sessionStart = session.startedAt, let recordingStart = recording.startedAt else { return 0 }
        return recordingStart.timeIntervalSince(sessionStart)
    }

    private nonisolated static func trackState(for result: AARTrackLoadResult) -> TrackState {
        switch result {
        case .loaded(let path, let partial): .ready(path, partial: partial)
        case .notUploaded: .unavailable("보정 결과가 아직 올라오지 않았습니다.")
        case .floorPlanMismatch: .unavailable("다른 도면으로 보정된 결과입니다.")
        case .failed: .unavailable("동선 보정에 실패했습니다.")
        case .unavailable: .unavailable("동선을 불러오지 못했습니다.")
        }
    }

    /// 구독의 첫 값만 받고 구독을 끝낸다.
    private static func first<Value>(_ stream: AsyncThrowingStream<Value, Error>) async throws -> Value? {
        for try await value in stream { return value }
        return nil
    }
}

#if DEBUG
extension AARStore {
    #if canImport(UIKit)
    /// SwiftUI Preview에서 동선 성공·실패 표시를 서버 없이 구성한다.
    func configureMovementPreview(
        floorPlanImage: UIImage,
        tracks: [String: TrackState],
        playbackPosition: Double
    ) {
        self.floorPlanImage = floorPlanImage
        floorPlanImageSize = floorPlanImage.size
        self.tracks = tracks
        self.playbackPosition = playbackPosition
        playbackDuration = tracks.values.compactMap { state in
            guard case .ready(let path, _) = state else { return nil }
            return path.endTime
        }.max() ?? 0
    }
    #endif

    /// 시험 데이터로 AAR을 바로 열 때 세션과 참가자를 한 번 받는다.
    func debugSnapshot(sessionID: UUID) async -> (session: Session, members: [Member])? {
        do {
            guard let session = try await Self.first(sessionRepository.observeSession(id: sessionID)) else { return nil }
            let members = try await Self.first(memberRepository.observeMembers(sessionID: sessionID)) ?? []
            return (session, members)
        } catch {
            Self.logger.error("AAR 시험 세션 불러오기 실패: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }
}
#endif

/// Preview에서 Firebase 없이 Store를 생성하기 위한 빈 Repository다.
struct DemoAARRecordingRepository: RecordingRepository {
    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {}
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
}

/// Preview에서 Firebase 없이 Store를 생성하기 위한 빈 Repository다.
struct DemoVideoChunkRepository: VideoChunkRepository {
    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {}
    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] {
        throw RepositoryError.notFound
    }
    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {}
}

/// Preview에서 Firebase 없이 Store를 생성하기 위한 빈 Repository다.
struct DemoTrackResultRepository: TrackResultRepository {
    func upload(_ result: TrackResultDocument) async throws {}
    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument { throw RepositoryError.notFound }
}
