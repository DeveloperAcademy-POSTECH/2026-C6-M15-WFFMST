import Foundation
import Testing
import CQBCore
import CQBFixtures

private func recordingTestResult(_ example: TrackContractFixture.Case = .trackingGap) throws -> ValidatedTrackResult {
    let map = try contractTrackMap()
    let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(example), floorPlan: map)
    var result = try TrackContractFixture.resultDocument(example)
    result.warnings.append(.headingAmbiguous)
    return try TrackDocumentValidator.result(TrackDocumentJSON.encode(result), raw: raw, floorPlan: map)
}

private func recordingRoundTrip<T: Codable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

private func recordingJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
}

struct RecordingModelTests {
    @Test func validatedSummaryPreservesResultMetadataWithoutCopyingGeometry() throws {
        let validated = try recordingTestResult()
        let result = validated.document
        let finishedAt = Date(timeIntervalSince1970: 1_800_000_020)
        let summary = TrackResultSummary(validatedResult: validated, finishedAt: finishedAt)
        let fieldInitialized = TrackResultSummary(identity: result.identity, resultID: result.resultID,
            floorPlan: result.floorPlan, sourceRawSHA256: result.sourceRawSHA256,
            algorithm: result.algorithm, status: result.status, searchIncomplete: result.searchIncomplete,
            warnings: result.warnings, failureReason: result.failureReason, finishedAt: finishedAt)

        #expect(summary == fieldInitialized)
        #expect(try recordingRoundTrip(summary) == summary)
        #expect(summary.status == .partial)
        #expect(summary.warnings.contains(.headingAmbiguous))
        let json = try recordingJSONObject(summary)
        #expect(json["vertices"] == nil)
        #expect(json["sampleCoverage"] == nil)
        #expect(json["unresolvedIntervals"] == nil)
    }

    @Test func completedAttemptCanCarryAFailedResultDocument() throws {
        let summary = TrackResultSummary(validatedResult: try recordingTestResult(.insufficientMovement))
        let attempt = ReconstructionAttempt(resultID: summary.resultID, state: .completed, result: summary)
        #expect(try recordingRoundTrip(attempt) == attempt)
        #expect(attempt.state == .completed)
        #expect(attempt.result?.status == .failed)
        #expect(attempt.result?.failureReason == .insufficientMovement)
        #expect(attempt.result?.finishedAt == nil)
    }

    @Test func recordingWithoutResultsRoundTripsItsUnavailableMetadata() throws {
        let raw = try TrackContractFixture.rawDocument(.normal)
        let signalAt = Date(timeIntervalSince1970: 1_800_000_000)
        let recording = Recording(identity: raw.identity, floorPlan: raw.floorPlan,
            signalReceivedDeviceAt: signalAt, recordingStartedDeviceAt: signalAt.addingTimeInterval(0.4),
            rawUploaded: false, state: .recording)
        let decoded = try recordingRoundTrip(recording)

        #expect(decoded == recording)
        #expect(decoded.id == raw.identity.recordingID)
        #expect(decoded.id != raw.identity.memberID)
        #expect(decoded.recordingEndedDeviceAt == nil && decoded.endReason == nil)
        #expect(decoded.video == nil && decoded.latestAttempt == nil)
        #expect(decoded.selectedResult == nil && decoded.selectedResultID == nil)
        let json = try recordingJSONObject(recording)
        #expect(json["id"] == nil && json["selectedResultID"] == nil)
    }

    @Test func failedOrCancelledNewAttemptKeepsPriorPartialSelectionInSnapshot() throws {
        let selected = TrackResultSummary(validatedResult: try recordingTestResult())
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let video = VideoInfo(codec: "hevc", width: 1280, height: 720, fps: 30,
            chunkSeconds: 10, totalChunks: 2, uploadedChunks: 2)
        let states: [ReconstructionAttemptState] = [.failed, .cancelled]
        for state in states {
            let attempt = ReconstructionAttempt(resultID: UUID(), state: state)
            let recording = Recording(identity: selected.identity, floorPlan: selected.floorPlan,
                signalReceivedDeviceAt: startedAt, recordingStartedDeviceAt: startedAt,
                recordingEndedDeviceAt: startedAt.addingTimeInterval(15.5), endReason: .signal,
                rawUploaded: true, video: video, latestAttempt: attempt, selectedResult: selected, state: .done)
            let decoded = try recordingRoundTrip(recording)

            #expect(decoded == recording)
            #expect(decoded.latestAttempt?.result == nil)
            #expect(decoded.latestAttempt?.resultID != decoded.selectedResultID)
            #expect(decoded.selectedResultID == selected.resultID)
            #expect(decoded.selectedResult?.status == .partial)
            #expect(decoded.selectedResult?.warnings == selected.warnings)
        }
    }

    @Test func chunkZeroIsDistinctForDifferentRecordingsOfTheSameMember() throws {
        let firstIdentity = try TrackContractFixture.rawDocument(.normal).identity
        let secondIdentity = TrackIdentity(sessionID: firstIdentity.sessionID,
            memberID: firstIdentity.memberID, recordingID: UUID())
        let first = VideoChunk(identity: firstIdentity, index: 0, startSeconds: 0, durationSeconds: 10,
            uploadedAt: Date(timeIntervalSince1970: 1_800_000_010))
        let second = VideoChunk(identity: secondIdentity, index: 0, startSeconds: 0, durationSeconds: 5.5)

        #expect(first.id != second.id)
        #expect(Set([first.id, second.id]).count == 2)
        #expect(first.id == VideoChunk.ID(identity: firstIdentity, index: 0))
        #expect(try recordingRoundTrip(first) == first)
        #expect(try recordingRoundTrip(second) == second)
        #expect(try recordingRoundTrip(first.id) == first.id)
        #expect(second.uploadedAt == nil)
        #expect(try recordingJSONObject(first)["id"] == nil)
    }

    @Test func videoTotalCanRemainUnknownWhileUploadedCountIsAvailable() throws {
        let video = VideoInfo(codec: "hevc", width: 1280, height: 720, fps: 30,
            chunkSeconds: 10, uploadedChunks: 1)
        let decoded = try recordingRoundTrip(video)
        #expect(decoded == video)
        #expect(decoded.totalChunks == nil)
        #expect(decoded.uploadedChunks == 1)
    }

    @Test func recordingAndVideoRequireIdentityAndTimingFieldsInJSON() throws {
        let raw = try TrackContractFixture.rawDocument(.normal)
        let recording = Recording(identity: raw.identity, floorPlan: raw.floorPlan,
            signalReceivedDeviceAt: Date(timeIntervalSince1970: 1_800_000_000),
            recordingStartedDeviceAt: Date(timeIntervalSince1970: 1_800_000_001),
            rawUploaded: false, state: .recording)
        for field in ["identity", "floorPlan", "signalReceivedDeviceAt", "recordingStartedDeviceAt", "state"] {
            var json = try recordingJSONObject(recording)
            json.removeValue(forKey: field)
            let data = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(Recording.self, from: data) }
        }
        let chunk = VideoChunk(identity: raw.identity, index: 0, startSeconds: 0, durationSeconds: 10)
        for field in ["identity", "index", "startSeconds", "durationSeconds"] {
            var json = try recordingJSONObject(chunk)
            json.removeValue(forKey: field)
            let data = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(VideoChunk.self, from: data) }
        }
    }

    @Test func knownEnumsRoundTripAndUnknownValuesAreRejected() throws {
        for state in [RecordingState.recording, .uploading, .done] {
            #expect(try recordingRoundTrip(state) == state)
        }
        for reason in [EndReason.signal, .manual, .error] {
            #expect(try recordingRoundTrip(reason) == reason)
        }
        for state in [ReconstructionAttemptState.pending, .running, .completed, .failed, .cancelled] {
            #expect(try recordingRoundTrip(state) == state)
        }
        let unknown = Data("\"future-state\"".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RecordingState.self, from: unknown) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EndReason.self, from: unknown) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ReconstructionAttemptState.self, from: unknown) }
    }
}
