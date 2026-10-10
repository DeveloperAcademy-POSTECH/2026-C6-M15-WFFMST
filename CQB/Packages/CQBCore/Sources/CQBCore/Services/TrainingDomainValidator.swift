import Foundation

public enum TrainingDomainValidationError: Error, Equatable, Sendable {
    case invalidSession, invalidMember, invalidTime, invalidVideo
    case identityMismatch, referenceMismatch, invalidSummary, invalidAttempt, invalidSelection
}

/// Minimum snapshot/relationship checks, not a state machine, readiness rule,
/// authorization check, upload receipt or replacement for TrackDocumentValidator.
/// Construction and Codable decoding alone do not perform these checks.
public enum TrainingDomainValidator {
    public static func validate(_ session: Session) throws {
        guard !session.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              session.pin.utf8.count == 6,
              session.pin.utf8.allSatisfy({ (48...57).contains($0) }),
              Set(session.excludedMemberIDs).count == session.excludedMemberIDs.count else {
            throw TrainingDomainValidationError.invalidSession
        }
        try finite(session.createdAt)
        if let start = session.startedAt { try ordered(session.createdAt, start) }
        if let end = session.endedAt { try ordered(session.startedAt ?? session.createdAt, end) }
        // Do not invent pre-start cancellation or status-transition policies.
        // The producer is responsible for the meaning of the reported status.
    }

    public static func validate(_ member: Member, in session: Session,
                                floorPlan: ValidatedFloorPlan) throws {
        guard member.sessionID == session.id else { throw TrainingDomainValidationError.identityMismatch }
        guard session.floorPlan == floorPlan.reference else { throw TrainingDomainValidationError.referenceMismatch }
        guard !member.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              member.clockOffsetToServer?.isFinite ?? true else {
            throw TrainingDomainValidationError.invalidMember
        }
        try finite(member.joinedAt)
        if let configuration = member.startConfiguration {
            try validate(configuration, floorPlan: floorPlan)
        }
    }

    public static func validate(_ configuration: MemberStartConfiguration,
                                floorPlan: ValidatedFloorPlan) throws {
        guard configuration.floorPlan == floorPlan.reference else {
            throw TrainingDomainValidationError.referenceMismatch
        }
        let width = floorPlan.manifest.imageWidth, height = floorPlan.manifest.imageHeight
        let start = try FloorPlanGeometry.imagePoint(from: configuration.positionNormalized, width: width, height: height)
        let direction = try FloorPlanGeometry.imagePoint(from: configuration.directionPointNormalized, width: width, height: height)
        try floorPlan.validateStart(at: start)
        guard hypot(direction.x - start.x, direction.y - start.y) >= 10 else {
            throw TrackCoordinateError.invalidAlignment
        }
        // Same pre-camera geometry as TrackCoordinateTransform, without a fake heading.
    }

    public static func validate(_ status: DeviceStatus, for member: Member) throws {
        guard status.sessionID == member.sessionID, status.memberID == member.id else {
            throw TrainingDomainValidationError.identityMismatch
        }
        try finite(status.updatedAt)
        // Reports can arrive separately from Member updates. Do not calculate
        // readiness or turn an old report into proof of a valid start setting.
    }

    public static func validate(_ video: VideoInfo) throws {
        guard !video.codec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              video.width > 0, video.height > 0, video.fps > 0,
              video.chunkSeconds.isFinite, video.chunkSeconds > 0, video.uploadedChunks >= 0 else {
            throw TrainingDomainValidationError.invalidVideo
        }
        if let total = video.totalChunks, total < 0 || video.uploadedChunks > total {
            throw TrainingDomainValidationError.invalidVideo
        }
    }

    public static func validate(_ chunk: VideoChunk) throws {
        guard chunk.index >= 0, chunk.startSeconds.isFinite, chunk.startSeconds >= 0,
              chunk.durationSeconds.isFinite, chunk.durationSeconds > 0,
              (chunk.startSeconds + chunk.durationSeconds).isFinite else {
            throw TrainingDomainValidationError.invalidVideo
        }
        if let uploaded = chunk.uploadedAt { try finite(uploaded) }
    }

    /// Accepts a loaded subset of chunks; does not infer upload progress from its count.
    public static func validate(_ chunks: [VideoChunk], for recording: Recording) throws {
        var ids = Set<VideoChunk.ID>()
        for chunk in chunks {
            try validate(chunk)
            guard chunk.identity == recording.identity else { throw TrainingDomainValidationError.identityMismatch }
            guard ids.insert(chunk.id).inserted,
                  recording.video?.totalChunks.map({ chunk.index < $0 }) ?? true else {
                throw TrainingDomainValidationError.invalidVideo
            }
        }
    }

    public static func validate(_ summary: TrackResultSummary) throws {
        guard summary.sourceRawSHA256.utf8.count == 64,
              summary.sourceRawSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              [summary.algorithm.name, summary.algorithm.version, summary.algorithm.settingsID]
                .allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              summary.status == .failed || summary.failureReason == nil else {
            throw TrainingDomainValidationError.invalidSummary
        }
        if let finished = summary.finishedAt { try finite(finished) }
        // No path/coverage is present here. Never recompute done/partial from a summary.
    }

    /// When the full result is available, compare all copied contract fields.
    /// finishedAt is external metadata, absent from TrackResultDocument.
    public static func validate(_ summary: TrackResultSummary, matches result: ValidatedTrackResult) throws {
        try validate(summary)
        guard summary == TrackResultSummary(validatedResult: result, finishedAt: summary.finishedAt) else {
            throw TrainingDomainValidationError.invalidSummary
        }
    }

    public static func validate(_ recording: Recording, for member: Member, in session: Session) throws {
        guard member.sessionID == session.id, recording.identity.sessionID == session.id,
              recording.identity.memberID == member.id else { throw TrainingDomainValidationError.identityMismatch }
        guard recording.floorPlan == session.floorPlan else { throw TrainingDomainValidationError.referenceMismatch }
        try ordered(recording.signalReceivedDeviceAt, recording.recordingStartedDeviceAt)
        if let end = recording.recordingEndedDeviceAt { try ordered(recording.recordingStartedDeviceAt, end) }
        guard (recording.recordingEndedDeviceAt != nil) == (recording.endReason != nil) else {
            throw TrainingDomainValidationError.invalidTime
        }
        if let video = recording.video { try validate(video) }
        if let selected = recording.selectedResult {
            try validate(selected, for: recording)
            guard selected.status != .failed else { throw TrainingDomainValidationError.invalidSelection }
        }
        if let attempt = recording.latestAttempt {
            switch attempt.state {
            case .completed:
                guard let result = attempt.result, result.resultID == attempt.resultID else {
                    throw TrainingDomainValidationError.invalidAttempt
                }
                try validate(result, for: recording)
            case .pending, .running, .failed, .cancelled:
                guard attempt.result == nil else { throw TrainingDomainValidationError.invalidAttempt }
            }
            if let selected = recording.selectedResult, selected.resultID == attempt.resultID {
                guard attempt.state == .completed, attempt.result == selected else {
                    throw TrainingDomainValidationError.invalidSelection
                }
            }
        }
    }

    private static func validate(_ summary: TrackResultSummary, for recording: Recording) throws {
        try validate(summary)
        guard summary.identity == recording.identity else { throw TrainingDomainValidationError.identityMismatch }
        guard summary.floorPlan == recording.floorPlan else { throw TrainingDomainValidationError.referenceMismatch }
    }

    private static func finite(_ date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw TrainingDomainValidationError.invalidTime }
    }

    private static func ordered(_ earlier: Date, _ later: Date) throws {
        try finite(earlier)
        try finite(later)
        guard earlier <= later else { throw TrainingDomainValidationError.invalidTime }
    }
}
