import Foundation
import Testing
import CQBCore
import CQBFixtures

struct AARTrainingDomainFixtureTests {
    @Test func completeRosterAndInitialAARSettingsAreDeterministicAndSurviveSnapshotCodec() throws {
        let map = try contractTrackMap()
        let sample = try TrainingDomainFixture.make(floorPlan: map)
        let repeated = try TrainingDomainFixture.make(floorPlan: map)
        #expect(sample.members == repeated.members)
        #expect(sample.aarSettings == repeated.aarSettings)
        let decoded = try JSONDecoder().decode(TrainingDomainFixture.Snapshot.self,
                                              from: JSONEncoder().encode(sample))
        #expect(decoded.members == sample.members)
        #expect(decoded.aarSettings == sample.aarSettings)
        #expect(decoded.member == sample.member)

        #expect(sample.members.count == 7)
        #expect(Set(sample.members.map(\.id)).count == 7)
        #expect(sample.session.excludedMemberIDs.count == 1)
        #expect(sample.members.filter { $0.id == sample.member.id } == [sample.member])
        let activeIDs = Set(sample.members.map(\.id)).subtracting(sample.session.excludedMemberIDs)
        #expect(activeIDs.count == 6)
        #expect(sample.aarSettings.sessionID == sample.session.id)
        #expect(sample.aarSettings.displayMode == .movement)
        #expect(sample.aarSettings.selectedMemberIDs == activeIDs)
        #expect(sample.aarSettings.selectedMemberIDs.contains(sample.member.id))
        #expect(sample.aarSettings.selectedMemberIDs.isDisjoint(with: sample.session.excludedMemberIDs))
        for member in sample.members {
            try TrainingDomainValidator.validate(member, in: sample.session, floorPlan: map)
        }
        try TrainingDomainValidator.validate(sample.aarSettings, in: sample.session, members: sample.members)
    }

    @Test func completeFixtureSupportsEmptySelectionsAndTheSameFourMembersInBothModes() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        let additional = sample.members.filter {
            $0.id != sample.member.id && sample.aarSettings.selectedMemberIDs.contains($0.id)
        }
        let four = Set([sample.member.id] + additional.prefix(3).map(\.id))
        #expect(four.count == 4)
        for mode in [AARDisplayMode.movement, .video] {
            let empty = AARSettings(sessionID: sample.session.id, selectedMemberIDs: [], displayMode: mode)
            let selected = AARSettings(sessionID: sample.session.id, selectedMemberIDs: four, displayMode: mode)
            try TrainingDomainValidator.validate(empty, in: sample.session, members: sample.members)
            try TrainingDomainValidator.validate(selected, in: sample.session, members: sample.members)
            #expect(selected.selectedMemberIDs == four)
        }
        #expect(sample.aarSettings.selectedMemberIDs.count == 6)
        try TrainingDomainValidator.validate(sample.aarSettings, in: sample.session, members: sample.members)
    }

    @Test func rejectedFiveOrSixMemberVideoValuesDoNotTrimSelectionsOrMutateTheSnapshot() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        let original = sample
        let active = sample.members.filter { sample.aarSettings.selectedMemberIDs.contains($0.id) }
        for count in [5, 6] {
            let attempted = AARSettings(sessionID: sample.session.id,
                selectedMemberIDs: Set(active.prefix(count).map(\.id)), displayMode: .video)
            #expect(throws: TrainingDomainValidationError.invalidSelection) {
                try TrainingDomainValidator.validate(attempted, in: sample.session, members: sample.members)
            }
            #expect(attempted.selectedMemberIDs.count == count)
            #expect(attempted.displayMode == .video)
            #expect(sample == original)
        }
        #expect(sample.aarSettings.displayMode == .movement)
        #expect(sample.aarSettings.selectedMemberIDs.count == 6)
    }

    @Test func fixtureContextRejectsUnknownExcludedAndForeignSessionReferences() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        let excludedID = try #require(sample.session.excludedMemberIDs.first)
        let unknownID = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!
        #expect(!sample.members.contains { $0.id == unknownID })
        for selectedID in [unknownID, excludedID] {
            let invalid = AARSettings(sessionID: sample.session.id,
                                      selectedMemberIDs: [selectedID], displayMode: .movement)
            #expect(throws: TrainingDomainValidationError.invalidSelection) {
                try TrainingDomainValidator.validate(invalid, in: sample.session, members: sample.members)
            }
        }
        let foreignSessionID = UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!
        let foreignSettings = AARSettings(sessionID: foreignSessionID,
            selectedMemberIDs: sample.aarSettings.selectedMemberIDs, displayMode: .movement)
        #expect(throws: TrainingDomainValidationError.identityMismatch) {
            try TrainingDomainValidator.validate(foreignSettings, in: sample.session, members: sample.members)
        }
        let foreignMember = Member(id: sample.member.id, sessionID: foreignSessionID,
            name: sample.member.name, displayName: sample.member.displayName,
            joinedAt: sample.member.joinedAt, clockOffsetToServer: sample.member.clockOffsetToServer,
            startConfiguration: sample.member.startConfiguration)
        let foreignRoster = sample.members.map { $0.id == sample.member.id ? foreignMember : $0 }
        #expect(throws: TrainingDomainValidationError.identityMismatch) {
            try TrainingDomainValidator.validate(sample.aarSettings, in: sample.session, members: foreignRoster)
        }
    }

    @Test func displayedMembersJoinRecordingsAndTheirSelectedResultsWithoutUsingLatestAttemptIDs() throws {
        let map = try contractTrackMap()
        let sample = try TrainingDomainFixture.make(floorPlan: map)
        let settings = sample.aarSettings
        let displayedMembers = sample.members.filter {
            $0.sessionID == settings.sessionID && settings.selectedMemberIDs.contains($0.id)
        }
        let displayedIDs = Set(displayedMembers.map(\.id))
        let recordings = sample.recordings.filter {
            $0.identity.sessionID == settings.sessionID && displayedIDs.contains($0.identity.memberID)
        }
        #expect(displayedMembers.count == 6)
        #expect(recordings.count == 3)
        #expect(recordings.allSatisfy { $0.identity.memberID == sample.member.id })
        let withSelections = recordings.filter { $0.selectedResultID != nil }
        #expect(withSelections.count == 2)
        var observedWarnings: [TrackResultWarning] = []
        for recording in withSelections {
            let selectedID = try #require(recording.selectedResultID)
            let sourceResult = try #require(sample.resultDocuments.first {
                $0.identity == recording.identity && $0.resultID == selectedID
            })
            let sourceRaw = try #require(sample.rawDocuments.first { $0.identity == recording.identity })
            let raw = try TrackDocumentValidator.raw(TrackDocumentJSON.encode(sourceRaw), floorPlan: map)
            let result = try TrackDocumentValidator.result(TrackDocumentJSON.encode(sourceResult), raw: raw, floorPlan: map)
            let summary = try #require(recording.selectedResult)
            try TrainingDomainValidator.validate(summary, matches: result)
            #expect(result.document == sourceResult)
            #expect(result.document.sampleCoverage == sourceResult.sampleCoverage)
            #expect(summary.status == .partial)
            #expect(summary.warnings == result.document.warnings)
            #expect(summary.sourceRawSHA256 == raw.sha256)
            observedWarnings.append(contentsOf: summary.warnings)
            let attempt = try #require(recording.latestAttempt)
            #expect(attempt.state == .failed || attempt.state == .cancelled)
            #expect(attempt.resultID != selectedID)
            #expect(attempt.result == nil)
            #expect(!sample.resultDocuments.contains { $0.resultID == attempt.resultID })
            if summary.warnings.contains(.trackingLost) {
                #expect(result.document.sampleCoverage.contains { $0.vertices == nil })
            }
            if summary.warnings.contains(.connectionUnverified) {
                #expect(result.document.sampleCoverage.allSatisfy { $0.vertices != nil })
                #expect(!result.document.unresolvedIntervals.isEmpty)
            }
        }
        #expect(observedWarnings.count == 2)
        #expect(observedWarnings.contains(.trackingLost))
        #expect(observedWarnings.contains(.connectionUnverified))
        let missing = try #require(recordings.first { $0.selectedResultID == nil })
        #expect(missing.video == nil)
        #expect(missing.latestAttempt == nil)
        #expect(!sample.rawDocuments.contains { $0.identity == missing.identity })
        #expect(!sample.resultDocuments.contains { $0.identity == missing.identity })
        #expect(!sample.chunks.contains { $0.identity == missing.identity })
    }

    @Test func selectedMembersWithoutAnyRecordingsRemainValidDisplayTargets() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        let missingMembers = sample.members.filter { member in
            sample.aarSettings.selectedMemberIDs.contains(member.id) &&
            !sample.recordings.contains {
                $0.identity.sessionID == member.sessionID && $0.identity.memberID == member.id
            }
        }
        #expect(missingMembers.count == 5)
        for member in missingMembers {
            #expect(!sample.rawDocuments.contains { $0.identity.memberID == member.id })
            #expect(!sample.resultDocuments.contains { $0.identity.memberID == member.id })
            #expect(!sample.chunks.contains { $0.identity.memberID == member.id })
        }
        let movement = AARSettings(sessionID: sample.session.id,
            selectedMemberIDs: Set(missingMembers.map(\.id)), displayMode: .movement)
        let video = AARSettings(sessionID: sample.session.id,
            selectedMemberIDs: Set(missingMembers.prefix(4).map(\.id)), displayMode: .video)
        try TrainingDomainValidator.validate(movement, in: sample.session, members: sample.members)
        try TrainingDomainValidator.validate(video, in: sample.session, members: sample.members)
        #expect(movement.selectedMemberIDs.count == 5)
        #expect(video.selectedMemberIDs.count == 4)
    }

    @Test func alternativeDisplaySettingsDoNotRewriteRecordingsResultsOrCarryPlaybackOffsets() throws {
        let sample = try TrainingDomainFixture.make(floorPlan: contractTrackMap())
        let recordings = sample.recordings
        let results = sample.resultDocuments
        let raw = sample.rawDocuments
        let chunks = sample.chunks
        let selectedResultIDs = recordings.compactMap(\.selectedResultID)
        let alternatives = [
            sample.aarSettings,
            AARSettings(sessionID: sample.session.id, selectedMemberIDs: [sample.member.id], displayMode: .video),
            AARSettings(sessionID: sample.session.id, selectedMemberIDs: [], displayMode: .movement)
        ]
        for settings in alternatives {
            try TrainingDomainValidator.validate(settings, in: sample.session, members: sample.members)
            let fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
            #expect(Set(fields.keys) == Set(["sessionID", "selectedMemberIDs", "displayMode"]))
            #expect(fields["selectedResultID"] == nil)
            #expect(fields["memberOffsets"] == nil && fields["manualOffset"] == nil)
        }
        #expect(sample.recordings == recordings)
        #expect(sample.resultDocuments == results)
        #expect(sample.rawDocuments == raw)
        #expect(sample.chunks == chunks)
        #expect(sample.recordings.compactMap(\.selectedResultID) == selectedResultIDs)
    }
}
