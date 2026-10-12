import CQBCore
import CoreGraphics
import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif

/// AAR 화면의 동선 불러오기와 재생 상태를 관리한다.
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

    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "AARStore")

    @ObservationIgnored private let sessionRepository: any SessionRepository
    @ObservationIgnored private let memberRepository: any MemberRepository
    @ObservationIgnored private let recordingRepository: any RecordingRepository
    @ObservationIgnored private let floorPlanFileRepository: any FloorPlanFileRepository
    @ObservationIgnored private let trackLoader: AARTrackLoader
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var loadedSessionID: UUID?

    /// 참가자 ID(`Member.id` 문자열)별 동선 상태
    private(set) var tracks: [String: TrackState] = [:]
    private(set) var playbackPosition = 0.0
    private(set) var playbackDuration = 0.0
    private(set) var isPlaying = false
    private(set) var isLoading = false
    /// 동선 좌표의 기준이 되는 도면 이미지 크기(픽셀)
    private(set) var floorPlanImageSize: CGSize?
#if canImport(UIKit)
    private(set) var floorPlanImage: UIImage?
#endif

    init(
        sessionRepository: any SessionRepository = DemoSessionRepository(),
        memberRepository: any MemberRepository = DemoMemberRepository(),
        recordingRepository: any RecordingRepository = DemoRecordingRepository(),
        trackResultRepository: any TrackResultRepository = DemoTrackResultRepository(),
        floorPlanFileRepository: any FloorPlanFileRepository = DemoFloorPlanFileRepository()
    ) {
        self.sessionRepository = sessionRepository
        self.memberRepository = memberRepository
        self.recordingRepository = recordingRepository
        self.floorPlanFileRepository = floorPlanFileRepository
        trackLoader = AARTrackLoader(repository: trackResultRepository)
    }

    var canPlay: Bool { playbackDuration > 0 && !isLoading }

    /// 현재 재생 위치에서 대원 점의 위치. 표시할 위치가 없으면 nil
    func position(for participantID: String) -> AARTrackPath.Position? {
        guard case .ready(let path, _) = tracks[participantID] else { return nil }
        return path.position(at: playbackPosition)
    }

    /// AAR에 들어갈 때 한 번 부른다. 같은 세션은 다시 받지 않는다.
    /// - Parameter localFloorPlan: 이 기기에 등록된 도면. 세션 도면과 같으면 내려받지 않고 쓴다
    func load(session: Session, participantIDs: [String], localFloorPlan: LocalRegisteredFloorPlan?) async {
        guard loadedSessionID != session.id else { return }
        reset()
        loadedSessionID = session.id
        isLoading = true
        tracks = Dictionary(uniqueKeysWithValues: participantIDs.map { ($0, TrackState.loading) })
        defer { isLoading = false }

        // 도면과 동선은 서로 기다릴 필요가 없어 함께 받기 시작한다.
        // 세션 시작 시각과 기록 목록은 AAR에 들어갈 때 한 번만 받는다.
        async let floorPlanLoaded: Void = loadFloorPlan(session.floorPlan, local: localFloorPlan)
        async let latestSession = Self.first(sessionRepository.observeSession(id: session.id))
        async let recordings = Self.first(recordingRepository.observeRecordings(sessionID: session.id))
        do {
            let (sessionValue, recordingList) = try await (latestSession, recordings)
            if loadedSessionID == session.id {
                await loadTracks(session: sessionValue ?? session, recordings: recordingList ?? [], participantIDs: participantIDs)
            }
        } catch {
            if loadedSessionID == session.id {
                Self.logger.error("AAR 기록 불러오기 실패: \(error.localizedDescription, privacy: .private)")
                tracks = Dictionary(uniqueKeysWithValues: participantIDs.map { ($0, TrackState.unavailable("기록을 불러오지 못했습니다.")) })
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
    }

    /// AAR을 나갈 때 재생을 멈추고 불러온 동선을 비운다.
    func reset() {
        pause()
        loadedSessionID = nil
        tracks = [:]
        playbackPosition = 0
        playbackDuration = 0
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
        isPlaying = true
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
                    return
                }
            }
        }
    }

    private func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
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
        playbackDuration = tracks.values.compactMap { state -> Double? in
            guard case .ready(let path, _) = state else { return nil }
            return path.endTime
        }.max() ?? 0
    }

    private func loadFloorPlan(_ reference: FloorPlanReference, local: LocalRegisteredFloorPlan?) async {
        if let local, local.id == reference.floorPlanID {
            floorPlanImageSize = CGSize(width: local.image.width, height: local.image.height)
#if canImport(UIKit)
            floorPlanImage = UIImage(data: local.image.pngData)
#endif
            return
        }
        // 이 기기에 없는 도면(앱 재설치, 다른 iPad)은 Storage에서 받는다.
        do {
            let files = try await floorPlanFileRepository.download(reference)
            let manifest = try JSONDecoder().decode(FloorPlanManifest.self, from: files.navigationMapJSON)
            floorPlanImageSize = CGSize(width: manifest.imageWidth, height: manifest.imageHeight)
#if canImport(UIKit)
            floorPlanImage = UIImage(data: files.imagePNG)
#endif
        } catch {
            Self.logger.error("AAR 도면 불러오기 실패: \(error.localizedDescription, privacy: .private)")
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
struct DemoRecordingRepository: RecordingRepository {
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
struct DemoTrackResultRepository: TrackResultRepository {
    func upload(_ result: TrackResultDocument) async throws {}
    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument { throw RepositoryError.notFound }
}
