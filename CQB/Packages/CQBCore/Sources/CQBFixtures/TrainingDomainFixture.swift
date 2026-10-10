import Foundation
import CQBCore

/// Deterministic, hand-authored relationships for #20; no server, camera or V13
/// execution. Does not rewrite the original normal-v1/minimal-v1 resource bytes.
public enum TrainingDomainFixture {
    public struct Snapshot: Codable, Equatable, Sendable {
        public let session: Session
        /// The original member whose three recordings exercise result selection.
        /// The same value is included in members for existing fixture consumers.
        public let member: Member
        /// Complete synthetic roster: six participants and one excluded member.
        /// Only member has recording payloads; missing media does not erase intent.
        public let members: [Member]
        /// One valid initial value, not an AAR entry or transition implementation.
        public let aarSettings: AARSettings
        public let deviceStatus: DeviceStatus
        public let recordings: [Recording]
        public let chunks: [VideoChunk]
        public let rawDocuments: [RawTrackDocument]
        public let resultDocuments: [TrackResultDocument]
    }

    /// Supply the fully validated normal-v1 map; image decoding is caller-owned.
    public static func make(floorPlan: ValidatedFloorPlan) throws -> Snapshot {
        let missing = try track(resumed: false, floorPlan: floorPlan)
        let resumed = try track(resumed: true, floorPlan: floorPlan)
        let source = missing.raw.document
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(id: source.identity.sessionID, pin: "012345", name: "도메인 연결 Fixture",
            status: .running, createdAt: base.addingTimeInterval(-60), startedAt: base,
            excludedMemberIDs: [id(106)], floorPlan: floorPlan.reference)
        let member = Member(id: source.identity.memberID, sessionID: session.id,
            name: "Fixture 대원", displayName: "Fixture 대원", joinedAt: base.addingTimeInterval(-30),
            clockOffsetToServer: 0,
            startConfiguration: .init(floorPlan: floorPlan.reference,
                positionNormalized: source.startPose.positionNormalized,
                directionPointNormalized: source.startPose.directionPointNormalized))
        // These participants deliberately have no recording/video/result payload.
        // The last member is excluded; this does not simulate readiness decisions.
        let members = [member] + (101...106).map { suffix in
            Member(id: id(suffix), sessionID: session.id,
                name: "Fixture 대원 \(suffix - 99)", displayName: "Fixture 대원 \(suffix - 99)",
                joinedAt: base.addingTimeInterval(-30))
        }
        let aarSettings = AARSettings(sessionID: session.id,
            selectedMemberIDs: Set(members.map(\.id)).subtracting(session.excludedMemberIDs),
            displayMode: .movement)
        let deviceStatus = DeviceStatus(sessionID: session.id, memberID: member.id,
            startPointSet: true, trackingReady: true, recording: true, updatedAt: base.addingTimeInterval(10))
        let video = VideoInfo(codec: "h264", width: 1920, height: 1080, fps: 30,
            chunkSeconds: 10, totalChunks: 1, uploadedChunks: 1)
        let selected = [TrackResultSummary(validatedResult: missing.result),
                        TrackResultSummary(validatedResult: resumed.result)]
        let tracks = [missing, resumed]
        var recordings: [Recording] = []
        var chunks: [VideoChunk] = []
        for index in tracks.indices {
            let raw = tracks[index].raw.document
            let end = raw.samples.last!.time
            let started = base.addingTimeInterval(raw.recordingStartOffsetSeconds)
            let attempt = ReconstructionAttempt(resultID: id(index == 0 ? 21 : 22),
                state: index == 0 ? .failed : .cancelled)
            let recording = Recording(identity: raw.identity, floorPlan: floorPlan.reference,
                signalReceivedDeviceAt: base, recordingStartedDeviceAt: started,
                recordingEndedDeviceAt: started.addingTimeInterval(end), endReason: .error,
                rawUploaded: true, video: video, latestAttempt: attempt,
                selectedResult: selected[index], state: .done)
            recordings.append(recording)
            chunks.append(VideoChunk(identity: raw.identity, index: 0, startSeconds: 0,
                durationSeconds: end, uploadedAt: base.addingTimeInterval(5)))
        }
        // An additional value snapshot proves 'not produced yet' without fake
        // video metadata or a pending value inserted into TrackResultStatus.
        recordings.append(Recording(identity: .init(sessionID: session.id, memberID: member.id, recordingID: id(3)),
            floorPlan: floorPlan.reference, signalReceivedDeviceAt: base,
            recordingStartedDeviceAt: base.addingTimeInterval(10), rawUploaded: false, state: .recording))
        try TrainingDomainValidator.validate(session)
        for participant in members {
            try TrainingDomainValidator.validate(participant, in: session, floorPlan: floorPlan)
        }
        try TrainingDomainValidator.validate(aarSettings, in: session, members: members)
        try TrainingDomainValidator.validate(deviceStatus, for: member)
        for recording in recordings {
            try TrainingDomainValidator.validate(recording, for: member, in: session)
            try TrainingDomainValidator.validate(chunks.filter { $0.identity == recording.identity }, for: recording)
        }
        return Snapshot(session: session, member: member, members: members, aarSettings: aarSettings,
            deviceStatus: deviceStatus, recordings: recordings,
            chunks: chunks, rawDocuments: tracks.map { $0.raw.document },
            resultDocuments: tracks.map { $0.result.document })
    }

    private static func track(resumed: Bool, floorPlan: ValidatedFloorPlan)
        throws -> (raw: ValidatedRawTrack, result: ValidatedTrackResult) {
        var raw = try TrackContractFixture.rawDocument(.normal)
        raw.identity.recordingID = id(resumed ? 2 : 1)
        raw.recordingStartOffsetSeconds = resumed ? 2.4 : 0.4
        let times: [Double] = resumed ? [0, 1, 1, 2] : [0, 1, 1]
        raw.samples = times.enumerated().map { index, time in
            let missing = !resumed && index == 2
            return TrackRawSample(time: time, arTimestamp: 100 + time,
                arPosition: [raw.originMeters.x + Double(index), raw.originMeters.y, raw.originMeters.z],
                relativeMeters: missing ? nil : .init(x: Double(index), y: 0),
                trackingState: missing ? .relocalizing : .normal,
                segment: resumed && index >= 2 ? 2 : 1)
        }
        let checkedRaw = try TrackDocumentValidator.raw(TrackDocumentJSON.encode(raw), floorPlan: floorPlan)
        let vertices: [TrackResultVertex] = (0..<(resumed ? 4 : 2)).map { index in
            .init(t: times[index] + raw.recordingStartOffsetSeconds,
                point: .init(x: 100 + Double(index) * 10, y: 120),
                part: index >= 2 ? 1 : 0, sampleIndex: index, provenance: .correctedSample)
        }
        let diagnosticTime = 1 + raw.recordingStartOffsetSeconds
        let result = TrackResultDocument(identity: raw.identity, resultID: id(resumed ? 12 : 11),
            floorPlan: raw.floorPlan, sourceRawSHA256: checkedRaw.sha256,
            algorithm: .init(name: "hand-authored-domain-relations", version: "1", settingsID: "not-v13-execution"),
            status: .partial, vertices: vertices,
            sampleCoverage: [.init(samples: .init(from: 0, through: 1), vertices: .init(from: 0, through: 1)),
                .init(samples: .init(from: 2, through: resumed ? 3 : 2),
                    vertices: resumed ? .init(from: 2, through: 3) : nil)],
            unresolvedIntervals: [.init(from: diagnosticTime, to: diagnosticTime, bounds: .closed,
                reason: resumed ? .connectionUnverified : .trackingLost, samples: .init(from: 2, through: 2),
                sourceReason: resumed ? "연결 Fixture: 복구점 연결 미확인" : "연결 Fixture: 샘플 2 위치 없음")],
            searchIncomplete: false, warnings: [resumed ? .connectionUnverified : .trackingLost])
        let checkedResult = try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: checkedRaw, floorPlan: floorPlan)
        return (checkedRaw, checkedResult)
    }

    private static func id(_ suffix: Int) -> UUID {
        // Closed, fixed call sites only; these identifiers are not production ID allocation.
        UUID(uuidString: "20200000-0000-0000-0000-\(String(format: "%012d", suffix))")!
    }
}
