import Foundation
import Testing
import CQBCore
import CQBFixtures

struct TrainingDomainValidationTests {
    private let sessionID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let memberID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private let recordingID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sessionRequiresASixDigitASCIIPINNameAndUniqueExclusions() throws {
        let map = try contractTrackMap()
        try TrainingDomainValidator.validate(session(map.reference))
        for (pin, name, excluded) in [
            ("12345", "훈련", []), ("1234567", "훈련", []),
            ("12345A", "훈련", []), ("１２３４５６", "훈련", []),
            ("012345", " \n", []), ("012345", "훈련", [memberID, memberID])
        ] as [(String, String, [UUID])] {
            let value = Session(id: sessionID, pin: pin, name: name, status: .preparing,
                                createdAt: now, excludedMemberIDs: excluded, floorPlan: map.reference)
            #expect(throws: TrainingDomainValidationError.invalidSession) {
                try TrainingDomainValidator.validate(value)
            }
        }
    }

    @Test func sessionTimesMustBeFiniteAndOrderedWithoutInventingTransitions() throws {
        let map = try contractTrackMap()
        let cases: [(Date, Date?, Date?)] = [
            (Date(timeIntervalSinceReferenceDate: .nan), nil, nil),
            (now, now.addingTimeInterval(-1), nil),
            (now, now.addingTimeInterval(2), now.addingTimeInterval(1)),
            (now, nil, now.addingTimeInterval(-1))
        ]
        for (created, start, end) in cases {
            let value = Session(id: sessionID, pin: "012345", name: "훈련", status: .ended,
                                createdAt: created, startedAt: start, endedAt: end,
                                excludedMemberIDs: [], floorPlan: map.reference)
            #expect(throws: TrainingDomainValidationError.invalidTime) {
                try TrainingDomainValidator.validate(value)
            }
        }
        // A pre-start termination policy is intentionally outside this validator.
        let ended = Session(id: sessionID, pin: "012345", name: "훈련", status: .ended,
                            createdAt: now, endedAt: now, excludedMemberIDs: [], floorPlan: map.reference)
        try TrainingDomainValidator.validate(ended)
    }

    @Test func memberAllowsUnmeasuredOrNegativeClockButChecksSessionAndMap() throws {
        let map = try contractTrackMap()
        let session = session(map.reference)
        for offset in [nil, -2.5, 0] as [TimeInterval?] {
            let value = Member(id: memberID, sessionID: session.id, name: "대원",
                               displayName: "대원 1", joinedAt: now, clockOffsetToServer: offset)
            try TrainingDomainValidator.validate(value, in: session, floorPlan: map)
        }
        for (name, offset) in [(" ", 0.0), ("대원", Double.infinity), ("대원", Double.nan)] {
            let value = Member(id: memberID, sessionID: session.id, name: name,
                               displayName: "대원 1", joinedAt: now, clockOffsetToServer: offset)
            #expect(throws: TrainingDomainValidationError.invalidMember) {
                try TrainingDomainValidator.validate(value, in: session, floorPlan: map)
            }
        }
        #expect(throws: TrainingDomainValidationError.identityMismatch) {
            try TrainingDomainValidator.validate(member(sessionID: UUID()), in: session, floorPlan: map)
        }
        #expect(throws: TrainingDomainValidationError.referenceMismatch) {
            try TrainingDomainValidator.validate(member(sessionID: session.id),
                                                  in: self.session(otherReference(map.reference)), floorPlan: map)
        }
        let invalidTime = Member(id: memberID, sessionID: session.id, name: "대원",
                                 displayName: "대원", joinedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        #expect(throws: TrainingDomainValidationError.invalidTime) {
            try TrainingDomainValidator.validate(invalidTime, in: session, floorPlan: map)
        }
    }

    @Test func startConfigurationChecksNormalizedCoordinatesFreeCellAndTenPixelDirection() throws {
        let map = try contractTrackMap() // 1000 x 600; (100,120) free, (220,120) blocked.
        let start = NormalizedPoint(x: 0.1, y: 0.2)
        let valid = MemberStartConfiguration(floorPlan: map.reference, positionNormalized: start,
                                            directionPointNormalized: NormalizedPoint(x: 0.11, y: 0.2))
        try TrainingDomainValidator.validate(valid, floorPlan: map)
        let tooShort = MemberStartConfiguration(floorPlan: map.reference, positionNormalized: start,
                                               directionPointNormalized: NormalizedPoint(x: 0.109, y: 0.2))
        #expect(throws: TrackCoordinateError.invalidAlignment) {
            try TrainingDomainValidator.validate(tooShort, floorPlan: map)
        }
        let blocked = MemberStartConfiguration(floorPlan: map.reference,
            positionNormalized: NormalizedPoint(x: 0.22, y: 0.2),
            directionPointNormalized: NormalizedPoint(x: 0.3, y: 0.2))
        #expect(throws: FloorPlanValidationError.blockedStart) {
            try TrainingDomainValidator.validate(blocked, floorPlan: map)
        }
        for point in [NormalizedPoint(x: 1.1, y: 0.2), NormalizedPoint(x: .nan, y: 0.2)] {
            let invalid = MemberStartConfiguration(floorPlan: map.reference, positionNormalized: point,
                                                  directionPointNormalized: valid.directionPointNormalized)
            #expect(throws: FloorPlanValidationError.invalidCoordinate) {
                try TrainingDomainValidator.validate(invalid, floorPlan: map)
            }
        }
        let wrongMap = MemberStartConfiguration(floorPlan: otherReference(map.reference),
            positionNormalized: start, directionPointNormalized: valid.directionPointNormalized)
        #expect(throws: TrainingDomainValidationError.referenceMismatch) {
            try TrainingDomainValidator.validate(wrongMap, floorPlan: map)
        }
    }

    @Test func deviceReportValidationChecksIdentityAndTimeWithoutInferringReadiness() throws {
        let member = member(sessionID: sessionID) // No start configuration has arrived.
        let report = DeviceStatus(sessionID: sessionID, memberID: memberID,
            startPointSet: true, trackingReady: false, recording: true, updatedAt: now.addingTimeInterval(-60))
        try TrainingDomainValidator.validate(report, for: member)
        for (session, participant) in [(UUID(), memberID), (sessionID, UUID())] {
            let invalid = DeviceStatus(sessionID: session, memberID: participant,
                startPointSet: false, trackingReady: false, recording: false, updatedAt: now)
            #expect(throws: TrainingDomainValidationError.identityMismatch) {
                try TrainingDomainValidator.validate(invalid, for: member)
            }
        }
        let invalidTime = DeviceStatus(sessionID: sessionID, memberID: memberID,
            startPointSet: false, trackingReady: false, recording: false,
            updatedAt: Date(timeIntervalSinceReferenceDate: .nan))
        #expect(throws: TrainingDomainValidationError.invalidTime) {
            try TrainingDomainValidator.validate(invalidTime, for: member)
        }
    }

    @Test func videoMetadataAcceptsUnknownTotalsAndChecksCountersAndDimensions() throws {
        for (total, uploaded) in [(nil, 5), (0, 0), (2, 2)] as [(Int?, Int)] {
            try TrainingDomainValidator.validate(VideoInfo(codec: "h264", width: 1920, height: 1080,
                fps: 30, chunkSeconds: 10, totalChunks: total, uploadedChunks: uploaded))
        }
        let invalid = [
            VideoInfo(codec: " ", width: 1, height: 1, fps: 30, chunkSeconds: 10, uploadedChunks: 0),
            VideoInfo(codec: "h264", width: 0, height: 1, fps: 30, chunkSeconds: 10, uploadedChunks: 0),
            VideoInfo(codec: "h264", width: 1, height: 0, fps: 30, chunkSeconds: 10, uploadedChunks: 0),
            VideoInfo(codec: "h264", width: 1, height: 1, fps: 0, chunkSeconds: 10, uploadedChunks: 0),
            VideoInfo(codec: "h264", width: 1, height: 1, fps: 30, chunkSeconds: 0, uploadedChunks: 0),
            VideoInfo(codec: "h264", width: 1, height: 1, fps: 30, chunkSeconds: .infinity, uploadedChunks: 0),
            VideoInfo(codec: "h264", width: 1, height: 1, fps: 30, chunkSeconds: 10, uploadedChunks: -1),
            VideoInfo(codec: "h264", width: 1, height: 1, fps: 30, chunkSeconds: 10, totalChunks: -1, uploadedChunks: 0),
            VideoInfo(codec: "h264", width: 1, height: 1, fps: 30, chunkSeconds: 10, totalChunks: 0, uploadedChunks: 1)
        ]
        for value in invalid {
            #expect(throws: TrainingDomainValidationError.invalidVideo) { try TrainingDomainValidator.validate(value) }
        }
    }

    @Test func chunkTimesAndIndicesRejectNegativeNonfiniteAndOverflowValues() throws {
        let identity = identity()
        try TrainingDomainValidator.validate(VideoChunk(identity: identity, index: 0,
                                                         startSeconds: 0, durationSeconds: 0.5))
        for (index, start, duration) in [
            (-1, 0.0, 10.0), (0, -1.0, 10.0), (0, 0.0, 0.0),
            (0, Double.nan, 10.0), (0, 0.0, Double.infinity),
            (0, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        ] {
            let value = VideoChunk(identity: identity, index: index, startSeconds: start, durationSeconds: duration)
            #expect(throws: TrainingDomainValidationError.invalidVideo) { try TrainingDomainValidator.validate(value) }
        }
        let invalidTime = VideoChunk(identity: identity, index: 0, startSeconds: 0, durationSeconds: 1,
                                     uploadedAt: Date(timeIntervalSinceReferenceDate: .nan))
        #expect(throws: TrainingDomainValidationError.invalidTime) { try TrainingDomainValidator.validate(invalidTime) }
    }

    @Test func loadedChunksMustBelongToRecordingAndHaveUniqueInRangeIndices() throws {
        let map = try contractTrackMap()
        let identity = identity()
        let video = VideoInfo(codec: "h264", width: 1920, height: 1080, fps: 30,
                              chunkSeconds: 10, totalChunks: 3, uploadedChunks: 0)
        let recording = Recording(identity: identity, floorPlan: map.reference,
            signalReceivedDeviceAt: now, recordingStartedDeviceAt: now, rawUploaded: false, video: video, state: .uploading)
        let chunk = VideoChunk(identity: identity, index: 2, startSeconds: 20, durationSeconds: 2)
        try TrainingDomainValidator.validate([chunk], for: recording) // A subset is allowed.
        #expect(throws: TrainingDomainValidationError.invalidVideo) {
            try TrainingDomainValidator.validate([chunk, chunk], for: recording)
        }
        let outOfRange = VideoChunk(identity: identity, index: 3, startSeconds: 30, durationSeconds: 1)
        #expect(throws: TrainingDomainValidationError.invalidVideo) {
            try TrainingDomainValidator.validate([outOfRange], for: recording)
        }
        let other = VideoChunk(identity: TrackIdentity(sessionID: sessionID, memberID: memberID, recordingID: UUID()),
                               index: 2, startSeconds: 20, durationSeconds: 2)
        #expect(chunk.id != other.id)
        #expect(throws: TrainingDomainValidationError.identityMismatch) {
            try TrainingDomainValidator.validate([other], for: recording)
        }
        let unknownTotal = Recording(identity: identity, floorPlan: map.reference,
            signalReceivedDeviceAt: now, recordingStartedDeviceAt: now, rawUploaded: false,
            video: VideoInfo(codec: "h264", width: 1920, height: 1080, fps: 30,
                             chunkSeconds: 10, totalChunks: nil, uploadedChunks: 0), state: .recording)
        try TrainingDomainValidator.validate([outOfRange], for: unknownTotal)
    }

    @Test func recordingChecksScopeMapTimeAndPairedEndMetadata() throws {
        let map = try contractTrackMap()
        let session = session(map.reference), member = member(sessionID: sessionID)
        func value(identity: TrackIdentity, reference: FloorPlanReference,
                   start: Date, end: Date? = nil, reason: EndReason? = nil) -> Recording {
            Recording(identity: identity, floorPlan: reference, signalReceivedDeviceAt: now,
                recordingStartedDeviceAt: start, recordingEndedDeviceAt: end, endReason: reason,
                rawUploaded: false, state: .recording)
        }
        try TrainingDomainValidator.validate(value(identity: identity(), reference: map.reference, start: now),
                                             for: member, in: session)
        try TrainingDomainValidator.validate(value(identity: identity(), reference: map.reference,
            start: now, end: now.addingTimeInterval(10), reason: .manual), for: member, in: session)
        for invalidIdentity in [TrackIdentity(sessionID: UUID(), memberID: memberID, recordingID: recordingID),
                                TrackIdentity(sessionID: sessionID, memberID: UUID(), recordingID: recordingID)] {
            #expect(throws: TrainingDomainValidationError.identityMismatch) {
                try TrainingDomainValidator.validate(value(identity: invalidIdentity, reference: map.reference, start: now),
                                                     for: member, in: session)
            }
        }
        #expect(throws: TrainingDomainValidationError.referenceMismatch) {
            try TrainingDomainValidator.validate(value(identity: identity(), reference: otherReference(map.reference), start: now),
                                                 for: member, in: session)
        }
        for (start, end, reason) in [
            (now.addingTimeInterval(-1), nil, nil),
            (now, now.addingTimeInterval(-1), EndReason.manual),
            (now, now, nil), (now, nil, EndReason.signal),
            (Date(timeIntervalSinceReferenceDate: .nan), nil, nil)
        ] as [(Date, Date?, EndReason?)] {
            #expect(throws: TrainingDomainValidationError.invalidTime) {
                try TrainingDomainValidator.validate(value(identity: identity(), reference: map.reference,
                    start: start, end: end, reason: reason), for: member, in: session)
            }
        }
    }

    @Test func attemptStateRequiresConsistentResultAndPreservesOlderPartialSelection() throws {
        let map = try contractTrackMap()
        let session = session(map.reference), member = member(sessionID: sessionID)
        let selected = summary(map.reference, status: .partial)
        let failedResult = summary(map.reference, status: .failed, reason: .noCandidate)
        func value(_ attempt: ReconstructionAttempt?, selected: TrackResultSummary? = nil) -> Recording {
            Recording(identity: identity(), floorPlan: map.reference, signalReceivedDeviceAt: now,
                recordingStartedDeviceAt: now, rawUploaded: true,
                latestAttempt: attempt, selectedResult: selected, state: .done)
        }
        try TrainingDomainValidator.validate(value(.init(resultID: failedResult.resultID, state: .completed, result: failedResult)),
                                             for: member, in: session)
        try TrainingDomainValidator.validate(value(.init(resultID: selected.resultID, state: .completed, result: selected),
                                                   selected: selected), for: member, in: session)
        for state in [ReconstructionAttemptState.pending, .running, .failed, .cancelled] {
            let next = ReconstructionAttempt(resultID: UUID(), state: state)
            try TrainingDomainValidator.validate(value(next, selected: selected), for: member, in: session)
            let invalid = ReconstructionAttempt(resultID: selected.resultID, state: state, result: selected)
            #expect(throws: TrainingDomainValidationError.invalidAttempt) {
                try TrainingDomainValidator.validate(value(invalid), for: member, in: session)
            }
        }
        for attempt in [ReconstructionAttempt(resultID: UUID(), state: .completed),
                        ReconstructionAttempt(resultID: UUID(), state: .completed, result: selected)] {
            #expect(throws: TrainingDomainValidationError.invalidAttempt) {
                try TrainingDomainValidator.validate(value(attempt), for: member, in: session)
            }
        }
        #expect(throws: TrainingDomainValidationError.invalidSelection) {
            try TrainingDomainValidator.validate(value(nil, selected: failedResult), for: member, in: session)
        }
        #expect(throws: TrainingDomainValidationError.invalidSelection) {
            try TrainingDomainValidator.validate(value(.init(resultID: selected.resultID, state: .cancelled), selected: selected),
                                                 for: member, in: session)
        }
    }

    @Test func summaryRequiresValidMetadataAndMatchesTheValidatedDocument() throws {
        let map = try contractTrackMap()
        let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(.trackingGap), floorPlan: map)
        let result = try TrackDocumentValidator.result(TrackContractFixture.resultJSON(.trackingGap), raw: raw, floorPlan: map)
        let valid = TrackResultSummary(validatedResult: result, finishedAt: now)
        try TrainingDomainValidator.validate(valid, matches: result)
        // A structurally valid summary still cannot claim different result metadata.
        let tampered = TrackResultSummary(identity: valid.identity, resultID: valid.resultID,
            floorPlan: valid.floorPlan, sourceRawSHA256: valid.sourceRawSHA256,
            algorithm: valid.algorithm, status: valid.status, searchIncomplete: valid.searchIncomplete,
            warnings: [], failureReason: valid.failureReason, finishedAt: now)
        #expect(tampered.warnings != valid.warnings)
        #expect(throws: TrainingDomainValidationError.invalidSummary) {
            try TrainingDomainValidator.validate(tampered, matches: result)
        }
        for hash in ["abc", String(repeating: "A", count: 64), String(repeating: "g", count: 64)] {
            let invalid = TrackResultSummary(identity: valid.identity, resultID: valid.resultID,
                floorPlan: valid.floorPlan, sourceRawSHA256: hash, algorithm: valid.algorithm,
                status: .partial, searchIncomplete: false, warnings: [])
            #expect(throws: TrainingDomainValidationError.invalidSummary) { try TrainingDomainValidator.validate(invalid) }
        }
        #expect(throws: TrainingDomainValidationError.invalidSummary) {
            try TrainingDomainValidator.validate(summary(map.reference, status: .done, reason: .noCandidate))
        }
    }

    @Test func summaryRejectsWhitespaceOnlyAlgorithmFieldsLikeFullResultValidation() throws {
        let reference = try contractTrackMap().reference
        let base = summary(reference, status: .partial)
        for field in 0..<3 {
            var values = ["manual", "1", "test"]
            values[field] = " \n\t"
            let invalid = TrackResultSummary(identity: base.identity, resultID: base.resultID,
                floorPlan: reference, sourceRawSHA256: base.sourceRawSHA256,
                algorithm: .init(name: values[0], version: values[1], settingsID: values[2]),
                status: .partial, searchIncomplete: false, warnings: [])
            #expect(throws: TrainingDomainValidationError.invalidSummary) {
                try TrainingDomainValidator.validate(invalid)
            }
        }
    }

    private func session(_ reference: FloorPlanReference) -> Session {
        Session(id: sessionID, pin: "012345", name: "훈련", status: .preparing,
                createdAt: now, excludedMemberIDs: [], floorPlan: reference)
    }

    private func member(sessionID: UUID) -> Member {
        Member(id: memberID, sessionID: sessionID, name: "대원", displayName: "대원 1", joinedAt: now)
    }

    private func identity() -> TrackIdentity {
        TrackIdentity(sessionID: sessionID, memberID: memberID, recordingID: recordingID)
    }

    private func otherReference(_ reference: FloorPlanReference) -> FloorPlanReference {
        FloorPlanReference(floorPlanID: reference.floorPlanID, revisionID: UUID(), navigationSHA256: reference.navigationSHA256)
    }

    private func summary(_ reference: FloorPlanReference, status: TrackResultStatus,
                         reason: TrackUnresolvedReason? = nil) -> TrackResultSummary {
        TrackResultSummary(identity: identity(), resultID: UUID(), floorPlan: reference,
            sourceRawSHA256: String(repeating: "a", count: 64),
            algorithm: TrackAlgorithmIdentity(name: "manual", version: "1", settingsID: "test"),
            status: status, searchIncomplete: false, warnings: [], failureReason: reason)
    }
}
