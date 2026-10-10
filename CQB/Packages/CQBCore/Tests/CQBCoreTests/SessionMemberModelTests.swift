import Foundation
import Testing
import CQBCore

struct SessionMemberModelTests {
    private let sessionID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let memberID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private let floorPlan = FloorPlanReference(
        floorPlanID: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
        revisionID: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
        navigationSHA256: String(repeating: "a", count: 64))
    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sessionPublicInitializerAndCodecPreserveBindingAndTimes() throws {
        let value = Session(id: sessionID, pin: "012345", name: "훈련",
                            status: .ended, createdAt: timestamp,
                            startedAt: timestamp.addingTimeInterval(10),
                            endedAt: timestamp.addingTimeInterval(30),
                            excludedMemberIDs: [memberID], floorPlan: floorPlan)
        let decoded = try roundTrip(value)
        #expect(decoded == value)
        #expect(decoded.floorPlanBinding == SessionFloorPlanBinding(
            sessionID: sessionID, name: "훈련", floorPlan: floorPlan))
        #expect(decoded.pin == "012345")
    }

    @Test func sessionOptionalTimesRemainAbsentOrNullWithoutInventedDates() throws {
        let value = Session(id: sessionID, pin: "012345", name: "훈련",
                            status: .preparing, createdAt: timestamp,
                            excludedMemberIDs: [], floorPlan: floorPlan)
        #expect(try roundTrip(value) == value)
        var fields = try object(value)
        #expect(fields["startedAt"] == nil)
        #expect(fields["endedAt"] == nil)
        fields["startedAt"] = NSNull()
        fields["endedAt"] = NSNull()
        let decoded = try decode(Session.self, fields)
        #expect(decoded.startedAt == nil)
        #expect(decoded.endedAt == nil)
    }

    @Test func sessionStatusCodecRejectsUnsupportedCases() throws {
        for status in [SessionStatus.preparing, .waiting, .running, .ended] {
            #expect(try roundTrip(status) == status)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SessionStatus.self, from: Data("\"futureStatus\"".utf8))
        }
    }

    @Test func memberRetainsSessionIdentityAndSignedMeasuredOffset() throws {
        let configuration = MemberStartConfiguration(
            floorPlan: floorPlan,
            positionNormalized: NormalizedPoint(x: 0.25, y: 0.375),
            directionPointNormalized: NormalizedPoint(x: 0.5, y: 0.375))
        let value = Member(id: memberID, sessionID: sessionID, name: "홍길동",
                           displayName: "홍길동 2", joinedAt: timestamp,
                           clockOffsetToServer: -1.25, startConfiguration: configuration)
        let decoded = try roundTrip(value)
        #expect(decoded == value)
        #expect(decoded.id == memberID)
        #expect(decoded.sessionID == sessionID)
        #expect(decoded.clockOffsetToServer == -1.25)
        #expect(decoded.startConfiguration?.floorPlan == floorPlan)
    }

    @Test func memberUnknownClockAndPlacementStayNilForMissingOrNullFields() throws {
        let value = Member(id: memberID, sessionID: sessionID, name: "홍길동",
                           displayName: "홍길동", joinedAt: timestamp)
        #expect(try roundTrip(value) == value)
        var fields = try object(value)
        #expect(fields["clockOffsetToServer"] == nil)
        #expect(fields["startConfiguration"] == nil)
        fields["clockOffsetToServer"] = NSNull()
        fields["startConfiguration"] = NSNull()
        let decoded = try decode(Member.self, fields)
        #expect(decoded.clockOffsetToServer == nil)
        #expect(decoded.startConfiguration == nil)
    }

    @Test func preCaptureConfigurationRequiresMeasuredCameraWhenMakingTrackPose() throws {
        let value = MemberStartConfiguration(
            floorPlan: floorPlan,
            positionNormalized: NormalizedPoint(x: 0.25, y: 0.375),
            directionPointNormalized: NormalizedPoint(x: 0.5, y: 0.375))
        #expect(try roundTrip(value) == value)
        let measuredHeading = -0.625
        let pose = value.trackStartPose(cameraDirectionRadians: measuredHeading)
        #expect(pose.positionNormalized == value.positionNormalized)
        #expect(pose.directionPointNormalized == value.directionPointNormalized)
        #expect(pose.cameraDirectionRadians == measuredHeading)
        let fields = try object(value)
        #expect(fields["cameraDirectionRadians"] == nil)
        #expect(fields["arToMapRotationDegrees"] == nil)
    }

    @Test func deviceReportKeepsTrackingAndRecordingIndependent() throws {
        let value = DeviceStatus(sessionID: sessionID, memberID: memberID,
                                 startPointSet: true, trackingReady: false,
                                 recording: true, updatedAt: timestamp)
        let decoded = try roundTrip(value)
        #expect(decoded == value)
        #expect(decoded.sessionID == sessionID)
        #expect(decoded.memberID == memberID)
        #expect(!decoded.trackingReady && decoded.recording)
    }

    @Test func requiredFieldsCannotDisappearDuringDecoding() throws {
        let session = Session(id: sessionID, pin: "012345", name: "훈련",
                              status: .waiting, createdAt: timestamp,
                              excludedMemberIDs: [], floorPlan: floorPlan)
        try expectMissingFieldsRejected(session, keys: [
            "id", "pin", "name", "status", "createdAt", "excludedMemberIDs", "floorPlan"
        ])
        let member = Member(id: memberID, sessionID: sessionID, name: "홍길동",
                            displayName: "홍길동", joinedAt: timestamp)
        try expectMissingFieldsRejected(member, keys: [
            "id", "sessionID", "name", "displayName", "joinedAt"
        ])
        let configuration = MemberStartConfiguration(
            floorPlan: floorPlan,
            positionNormalized: NormalizedPoint(x: 0.25, y: 0.375),
            directionPointNormalized: NormalizedPoint(x: 0.5, y: 0.375))
        try expectMissingFieldsRejected(configuration, keys: [
            "floorPlan", "positionNormalized", "directionPointNormalized"
        ])
        let status = DeviceStatus(sessionID: sessionID, memberID: memberID,
                                  startPointSet: false, trackingReady: false,
                                  recording: false, updatedAt: timestamp)
        try expectMissingFieldsRejected(status, keys: [
            "sessionID", "memberID", "startPointSet", "trackingReady", "recording", "updatedAt"
        ])
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ fields: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: fields))
    }

    private func expectMissingFieldsRejected<T: Codable>(_ value: T, keys: [String]) throws {
        let original = try object(value)
        for key in keys {
            var fields = original
            fields.removeValue(forKey: key)
            #expect(throws: DecodingError.self) {
                try decode(T.self, fields)
            }
        }
    }
}
