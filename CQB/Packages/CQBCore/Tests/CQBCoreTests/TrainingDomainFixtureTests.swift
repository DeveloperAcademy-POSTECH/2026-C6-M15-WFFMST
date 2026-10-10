import Foundation
import Testing
import CQBCore
import CQBFixtures

struct TrainingDomainFixtureTests {
    @Test func fixtureIsDeterministicAndRoundTripsWithoutServerTypes() throws {
        let map = try contractTrackMap()
        let first = try TrainingDomainFixture.make(floorPlan: map)
        let second = try TrainingDomainFixture.make(floorPlan: map)
        #expect(first == second)
        let bytes = try JSONEncoder().encode(first)
        let decoded = try JSONDecoder().decode(TrainingDomainFixture.Snapshot.self, from: bytes)
        #expect(decoded == first)
    }

    @Test func sessionMemberRecordingsAndChunksShareOnlyIntendedIdentities() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        #expect(sample.session.floorPlanBinding.sessionID == sample.member.sessionID)
        #expect(sample.deviceStatus.memberID == sample.member.id)
        #expect(Set(sample.recordings.map(\.id)).count == 3)
        #expect(sample.recordings.allSatisfy { $0.identity.memberID == sample.member.id })
        #expect(sample.recordings.allSatisfy { $0.identity.sessionID == sample.session.id })
        #expect(sample.recordings.allSatisfy { $0.floorPlan == sample.session.floorPlan })
        #expect(sample.chunks.map(\.index) == [0, 0])
        #expect(Set(sample.chunks.map(\.id)).count == 2)
        let firstEnd = try #require(sample.recordings[0].recordingEndedDeviceAt)
        #expect(firstEnd < sample.recordings[1].recordingStartedDeviceAt)
    }

    @Test func captureSettingsAndResultSummariesMatchTheExistingContract() throws {
        let map = try contractTrackMap()
        let sample = try TrainingDomainFixture.make(floorPlan: map)
        let configuration = try #require(sample.member.startConfiguration)
        for index in sample.rawDocuments.indices {
            let document = sample.rawDocuments[index]
            let confirmed = configuration.trackStartPose(cameraDirectionRadians: document.startPose.cameraDirectionRadians)
            #expect(confirmed == document.startPose)
            let raw = try TrackDocumentValidator.raw(TrackDocumentJSON.encode(document), floorPlan: map)
            let result = try TrackDocumentValidator.result(TrackDocumentJSON.encode(sample.resultDocuments[index]), raw: raw, floorPlan: map)
            let summary = try #require(sample.recordings[index].selectedResult)
            try TrainingDomainValidator.validate(summary, matches: result)
            #expect(summary.sourceRawSHA256 == raw.sha256)
            #expect(summary.identity == sample.recordings[index].identity)
            #expect(summary.resultID == sample.recordings[index].selectedResultID)
            #expect(summary.status == .partial)
        }
    }

    @Test func equalTimeMissingSampleDoesNotEraseTheSolvedSampleInTheSummary() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        let raw = sample.rawDocuments[0], result = sample.resultDocuments[0]
        #expect(raw.samples[1].time == raw.samples[2].time)
        #expect(raw.samples[1].relativeMeters != nil && raw.samples[2].relativeMeters == nil)
        #expect(result.vertices[1].t == result.unresolvedIntervals[0].from)
        #expect(result.vertices[1].sampleIndex == 1)
        #expect(result.unresolvedIntervals[0].samples == .init(from: 2, through: 2))
        #expect(sample.recordings[0].selectedResult?.status == .partial)
        #expect(sample.recordings[0].selectedResult?.warnings == [.trackingLost])
    }

    @Test func fullyCoveredCoordinatesCanStillHavePartialConnectionDiagnostics() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        let result = sample.resultDocuments[1]
        #expect(result.sampleCoverage.allSatisfy { $0.vertices != nil })
        #expect(result.vertices[2].sampleIndex == result.unresolvedIntervals[0].samples.from)
        #expect(result.vertices[2].t == result.unresolvedIntervals[0].from)
        #expect(result.vertices[1].part != result.vertices[2].part)
        #expect(sample.recordings[1].selectedResult?.status == .partial)
        #expect(sample.recordings[1].selectedResult?.warnings == [.connectionUnverified])
    }

    @Test func failedAndCancelledAttemptsKeepOldSelectionsWhileNewRecordingHasNone() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        #expect(sample.recordings[0].latestAttempt?.state == .failed)
        #expect(sample.recordings[1].latestAttempt?.state == .cancelled)
        for recording in sample.recordings.prefix(2) {
            #expect(recording.latestAttempt?.result == nil)
            #expect(recording.latestAttempt?.resultID != recording.selectedResultID)
            #expect(recording.selectedResult?.status == .partial)
            #expect(recording.state == .done) // transfer completion is not correction success
        }
        #expect(sample.recordings[2].latestAttempt == nil)
        #expect(sample.recordings[2].selectedResultID == nil)
        #expect(sample.recordings[2].video == nil)
    }

    @Test func summaryDoesNotDuplicateLargeRoutePayloads() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        let summary = try #require(sample.recordings[0].selectedResult)
        let fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        #expect(fields["vertices"] == nil)
        #expect(fields["sampleCoverage"] == nil)
        #expect(fields["unresolvedIntervals"] == nil)
        #expect(fields["resultID"] != nil && fields["sourceRawSHA256"] != nil)
    }
}
