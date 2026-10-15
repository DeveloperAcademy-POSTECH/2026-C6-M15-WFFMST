import CQBCore
import Foundation

/// 기록 하나의 보정 결과를 받은 결과
nonisolated enum AARTrackLoadResult: Equatable, Sendable {
    /// 받았다. `partial`이면 일부 구간만 보정된 결과다
    case loaded(AARTrackPath, partial: Bool)
    /// 아직 올라오지 않았다. 다시 요청하면 새로 받는다
    case notUploaded
    /// 세션 도면과 다른 도면으로 보정된 결과다
    case floorPlanMismatch
    /// 대원 기기에서 보정에 실패했다
    case failed
    /// 네트워크 등으로 받지 못했다. 다시 요청하면 새로 받는다
    case unavailable
}

/// AAR에서 대원 동선을 받는다. 같은 기록은 한 번만 받고, 동시에 요청해도 한 번만 내려받는다.
actor AARTrackLoader {
    private let repository: any TrackResultRepository
    private var results: [UUID: AARTrackLoadResult] = [:]
    private var inFlight: [UUID: Task<AARTrackLoadResult, Never>] = [:]

    init(repository: any TrackResultRepository) {
        self.repository = repository
    }

    /// - Parameters:
    ///   - floorPlan: 세션의 도면. 결과의 도면과 다르면 `floorPlanMismatch`
    ///   - recordingOffset: 세션 시작부터 기록 시작까지의 초
    func load(_ identity: TrackIdentity, floorPlan: FloorPlanReference, recordingOffset: Double) async -> AARTrackLoadResult {
        let key = identity.recordingID
        if let result = results[key] { return result }
        if let task = inFlight[key] { return await task.value }

        let repository = repository
        let task = Task {
            await Self.download(identity, floorPlan: floorPlan, recordingOffset: recordingOffset, from: repository)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        // 다시 받으면 달라질 수 있는 결과(아직 없음, 네트워크 오류)는 저장하지 않는다.
        if result != .notUploaded, result != .unavailable {
            results[key] = result
        }
        return result
    }

    /// AAR을 마치면 받은 결과를 비운다.
    func reset() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        results = [:]
    }

    private static func download(
        _ identity: TrackIdentity,
        floorPlan: FloorPlanReference,
        recordingOffset: Double,
        from repository: any TrackResultRepository
    ) async -> AARTrackLoadResult {
        let document: TrackResultDocument
        do {
            document = try await repository.download(identity)
        } catch RepositoryError.notFound {
            return .notUploaded
        } catch {
            return .unavailable
        }

        guard document.floorPlan == floorPlan else { return .floorPlanMismatch }
        switch document.status {
        case .failed:
            return .failed
        case .done, .partial:
            let path = AARTrackPath(result: document, recordingOffset: recordingOffset)
            return .loaded(path, partial: document.status == .partial)
        }
    }
}
