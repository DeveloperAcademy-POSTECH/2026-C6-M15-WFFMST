import Foundation
import Testing
import CQBCore

struct AARSettingsTests {
    private let sessionID = UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!
    private let otherSessionID = UUID(uuidString: "a0000000-0000-4000-8000-000000000002")!
    private let memberIDs = [
        "b0000000-0000-4000-8000-000000000001",
        "b0000000-0000-4000-8000-000000000002",
        "b0000000-0000-4000-8000-000000000003",
        "b0000000-0000-4000-8000-000000000004",
        "b0000000-0000-4000-8000-000000000005",
        "b0000000-0000-4000-8000-000000000006"
    ].map { UUID(uuidString: $0)! }
    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func publicModelAndBothModesEncodeOnlyTheThreeContractFields() throws {
        for mode in [AARDisplayMode.movement, .video] {
            let value = AARSettings(sessionID: sessionID,
                                    selectedMemberIDs: Set(memberIDs.prefix(2)), displayMode: mode)
            let data = try JSONEncoder().encode(value)
            let fields = try object(data)
            #expect(Set(fields.keys) == Set(["sessionID", "selectedMemberIDs", "displayMode"]))
            #expect(fields["displayMode"] as? String == mode.rawValue)
            #expect(try JSONDecoder().decode(AARSettings.self, from: data) == value)
            #expect(try JSONDecoder().decode(AARDisplayMode.self, from: JSONEncoder().encode(mode)) == mode)
        }
    }

    @Test func everyContractFieldIsRequiredAndNonnullable() throws {
        let value = AARSettings(sessionID: sessionID, selectedMemberIDs: [], displayMode: .movement)
        let original = try object(JSONEncoder().encode(value))
        for key in ["sessionID", "selectedMemberIDs", "displayMode"] {
            var missing = original
            missing.removeValue(forKey: key)
            #expect(throws: DecodingError.self) { try decode(missing) }
            var null = original
            null[key] = NSNull()
            #expect(throws: DecodingError.self) { try decode(null) }
        }
    }

    @Test func malformedIdentitiesCollectionsAndUnknownModesAreRejectedByCodec() throws {
        let value = AARSettings(sessionID: sessionID,
                                selectedMemberIDs: [memberIDs[0]], displayMode: .movement)
        let original = try object(JSONEncoder().encode(value))
        let invalidFields: [(String, Any)] = [
            ("sessionID", "not-a-uuid"),
            ("sessionID", 123),
            ("selectedMemberIDs", memberIDs[0].uuidString),
            ("selectedMemberIDs", ["not-a-member-uuid"]),
            ("selectedMemberIDs", [123]),
            ("displayMode", "futureMode"),
            ("displayMode", 123)
        ]
        for (key, invalid) in invalidFields {
            var fields = original
            fields[key] = invalid
            #expect(throws: DecodingError.self) { try decode(fields) }
        }
    }

    @Test func selectedMembersRoundTripAsASetWithoutJSONOrderingRequirements() throws {
        let expected = AARSettings(sessionID: sessionID,
                                   selectedMemberIDs: Set(memberIDs.prefix(3)), displayMode: .movement)
        var fields = try object(JSONEncoder().encode(expected))
        fields["selectedMemberIDs"] = memberIDs.prefix(3).map(\.uuidString)
        let forward = try decode(fields)
        fields["selectedMemberIDs"] = memberIDs.prefix(3).reversed().map(\.uuidString)
        let reversed = try decode(fields)
        #expect(forward == expected)
        #expect(reversed == expected)
        #expect(try JSONDecoder().decode(AARSettings.self, from: JSONEncoder().encode(reversed)) == expected)
    }

    @Test func emptySelectionsFourVideoMembersAndLargerMovementSelectionsAreValid() throws {
        #expect(TrainingDomainValidator.maximumAARVideoMemberCount == 4)
        let session = session()
        let roster = members(6)
        for mode in [AARDisplayMode.movement, .video] {
            let empty = AARSettings(sessionID: sessionID, selectedMemberIDs: [], displayMode: mode)
            try TrainingDomainValidator.validate(empty, in: session, members: [])
            try TrainingDomainValidator.validate(empty, in: session, members: roster)
        }
        let video = AARSettings(sessionID: sessionID,
                                selectedMemberIDs: Set(memberIDs.prefix(4)), displayMode: .video)
        try TrainingDomainValidator.validate(video, in: session, members: roster)
        for count in [5, 6] {
            let movement = AARSettings(sessionID: sessionID,
                                       selectedMemberIDs: Set(memberIDs.prefix(count)), displayMode: .movement)
            try TrainingDomainValidator.validate(movement, in: session, members: roster)
        }
    }

    @Test func constructionAndDecodingDoNotValidateOrSilentlyTrimAnOversizedSelection() throws {
        let value = AARSettings(sessionID: sessionID,
                                selectedMemberIDs: Set(memberIDs.prefix(5)), displayMode: .video)
        let decoded = try JSONDecoder().decode(AARSettings.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
        let session = session()
        let roster = members(5)
        let originalSession = session
        let originalRoster = roster
        #expect(throws: TrainingDomainValidationError.invalidSelection) {
            try TrainingDomainValidator.validate(decoded, in: session, members: roster)
        }
        #expect(decoded == value)
        #expect(decoded.selectedMemberIDs.count == 5)
        #expect(decoded.displayMode == .video)
        #expect(session == originalSession)
        #expect(roster == originalRoster)
    }

    @Test func settingsAndEveryRosterMemberMustBelongToTheContextSession() throws {
        let session = session()
        let wrongSession = AARSettings(sessionID: otherSessionID, selectedMemberIDs: [], displayMode: .movement)
        #expect(throws: TrainingDomainValidationError.identityMismatch) {
            try TrainingDomainValidator.validate(wrongSession, in: session, members: [])
        }
        let empty = AARSettings(sessionID: sessionID, selectedMemberIDs: [], displayMode: .movement)
        let foreignMember = Member(id: memberIDs[0], sessionID: otherSessionID,
                                   name: "다른 세션 대원", displayName: "다른 세션 대원", joinedAt: timestamp)
        // An unselected foreign member still makes the supplied session roster invalid.
        #expect(throws: TrainingDomainValidationError.identityMismatch) {
            try TrainingDomainValidator.validate(empty, in: session, members: [foreignMember])
        }
    }

    @Test func duplicateRosterIdentitiesAreRejectedEvenWhenNothingIsSelected() throws {
        let roster = members(1)
        let settings = AARSettings(sessionID: sessionID, selectedMemberIDs: [], displayMode: .movement)
        #expect(throws: TrainingDomainValidationError.invalidMember) {
            try TrainingDomainValidator.validate(settings, in: session(), members: [roster[0], roster[0]])
        }
    }

    @Test func selectedMembersMustExistAndNotBeExcludedButUnselectedExclusionsAreAllowed() throws {
        let roster = members(2)
        let session = session(excludedMemberIDs: [memberIDs[1]])
        for selected in [[memberIDs[1]], [memberIDs[2]]] {
            let invalid = AARSettings(sessionID: sessionID,
                                      selectedMemberIDs: Set(selected), displayMode: .movement)
            #expect(throws: TrainingDomainValidationError.invalidSelection) {
                try TrainingDomainValidator.validate(invalid, in: session, members: roster)
            }
        }
        let valid = AARSettings(sessionID: sessionID,
                                selectedMemberIDs: [memberIDs[0]], displayMode: .movement)
        try TrainingDomainValidator.validate(valid, in: session, members: roster)
    }

    @Test func validationDoesNotRequireEndedSessionMeasuredClockOrStartConfiguration() throws {
        let roster = members(2)
        #expect(roster.allSatisfy { $0.clockOffsetToServer == nil && $0.startConfiguration == nil })
        let settings = AARSettings(sessionID: sessionID,
                                   selectedMemberIDs: Set(memberIDs.prefix(2)), displayMode: .video)
        // Settings describe display intent without requiring capture readiness or available media.
        for phase in [SessionStatus.preparing, .running] {
            try TrainingDomainValidator.validate(settings, in: session(status: phase), members: roster)
        }
    }

    @Test func bothDisplayModesCanRepresentExactlyTheSameMemberSelection() throws {
        let selected: Set<UUID> = [memberIDs[0], memberIDs[2]]
        let movement = AARSettings(sessionID: sessionID, selectedMemberIDs: selected, displayMode: .movement)
        let video = AARSettings(sessionID: sessionID, selectedMemberIDs: selected, displayMode: .video)
        let originalMovement = movement
        let originalVideo = video
        let session = session()
        let roster = members(3)
        try TrainingDomainValidator.validate(movement, in: session, members: roster)
        try TrainingDomainValidator.validate(video, in: session, members: roster)
        #expect(movement.selectedMemberIDs == video.selectedMemberIDs)
        #expect(movement == originalMovement)
        #expect(video == originalVideo)
        #expect(movement != video)
    }

    private func session(status: SessionStatus = .preparing, excludedMemberIDs: [UUID] = []) -> Session {
        Session(id: sessionID, pin: "012345", name: "AAR 단위 테스트", status: status,
                createdAt: timestamp,
                startedAt: status == .running ? timestamp.addingTimeInterval(1) : nil,
                excludedMemberIDs: excludedMemberIDs,
                floorPlan: FloorPlanReference(
                    floorPlanID: UUID(uuidString: "c0000000-0000-4000-8000-000000000001")!,
                    revisionID: UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!,
                    navigationSHA256: String(repeating: "a", count: 64)))
    }

    private func members(_ count: Int) -> [Member] {
        memberIDs.prefix(count).map { id in
            Member(id: id, sessionID: sessionID, name: "대원", displayName: "대원", joinedAt: timestamp)
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ fields: [String: Any]) throws -> AARSettings {
        try JSONDecoder().decode(AARSettings.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}
