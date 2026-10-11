import CQBCore
import FirebaseFirestore
import Foundation
import Testing
@testable import CQBFirebase

private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
private let memberID = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
private let recordingID = UUID(uuidString: "00000000-0000-0000-0000-000000000503")!
private let floorPlanID = UUID(uuidString: "00000000-0000-0000-0000-000000000504")!
private let time = Date(timeIntervalSince1970: 1_800_000_000)

private func isServerTimestamp(_ value: Any?) -> Bool {
    (value as? FieldValue) == FieldValue.serverTimestamp()
}

@Test("pins 문서는 세션 ID 문자열만 담는다")
func pinData() {
    let data = FirestoreEncoding.pin(sessionID: sessionID)

    #expect(data.count == 1)
    #expect(data["sessionID"] as? String == sessionID.uuidString)
}

@Test("Session은 UUID를 문자열, 도면 참조를 맵으로 바꾸고 instructorUid를 붙인다")
func sessionData() throws {
    let session = Session(
        id: sessionID, pin: "123456", name: "오후 훈련", status: .waiting,
        floorPlan: FloorPlanReference(floorPlanID: floorPlanID, navigationSHA256: "nav-sha")
    )

    let data = try FirestoreEncoding.session(session, instructorUid: "instructor-uid")
    let floorPlan = try #require(data["floorPlan"] as? [String: Any])

    #expect(data["id"] as? String == sessionID.uuidString)
    #expect(data["pin"] as? String == "123456")
    #expect(data["name"] as? String == "오후 훈련")
    #expect(data["status"] as? String == "waiting")
    #expect(data["startedAt"] == nil)
    #expect(floorPlan["floorPlanID"] as? String == floorPlanID.uuidString)
    #expect(floorPlan["navigationSHA256"] as? String == "nav-sha")
    #expect(data["instructorUid"] as? String == "instructor-uid")
}

@Test("훈련을 시작할 때만 Session.startedAt이 서버 시각이 된다")
func sessionStartedAtStamp() throws {
    let session = Session(
        id: sessionID, pin: "123456", name: "오후 훈련", status: .running, startedAt: time,
        floorPlan: FloorPlanReference(floorPlanID: floorPlanID, navigationSHA256: "nav-sha")
    )

    let kept = try FirestoreEncoding.session(session, instructorUid: "instructor-uid")
    let stamped = try FirestoreEncoding.session(session, instructorUid: "instructor-uid", stampStartedAt: true)

    #expect((kept["startedAt"] as? Timestamp)?.dateValue() == time)
    #expect(isServerTimestamp(stamped["startedAt"]))
}

@Test("Member는 uid와 입장 검증용 pin을 붙이고 lastActiveAt을 서버 시각으로 바꾼다")
func memberData() throws {
    let member = Member(id: memberID, sessionID: sessionID, name: "대원 1", isReady: true, lastActiveAt: time)

    let data = try FirestoreEncoding.member(member, uid: "member-uid", pin: "123456")

    #expect(data["id"] as? String == memberID.uuidString)
    #expect(data["sessionID"] as? String == sessionID.uuidString)
    #expect(data["name"] as? String == "대원 1")
    #expect(data["isReady"] as? Bool == true)
    #expect(isServerTimestamp(data["lastActiveAt"]))
    #expect(data["uid"] as? String == "member-uid")
    #expect(data["pin"] as? String == "123456")
}

@Test("Recording은 identity를 맵으로 바꾸고 lastActiveAt을 서버 시각으로 바꾼다")
func recordingData() throws {
    let recording = Recording(
        identity: TrackIdentity(sessionID: sessionID, memberID: memberID, recordingID: recordingID),
        state: .finishing, startedAt: time, lastActiveAt: time, videoChunkCount: 7
    )

    let data = try FirestoreEncoding.recording(recording)
    let identity = try #require(data["identity"] as? [String: Any])

    #expect(identity["sessionID"] as? String == sessionID.uuidString)
    #expect(identity["memberID"] as? String == memberID.uuidString)
    #expect(identity["recordingID"] as? String == recordingID.uuidString)
    #expect(data["state"] as? String == "finishing")
    #expect((data["startedAt"] as? Timestamp)?.dateValue() == time)
    #expect(isServerTimestamp(data["lastActiveAt"]))
    #expect(data["videoChunkCount"] as? Int == 7)
}

@Test("기록을 시작할 때 Recording.startedAt도 서버 시각이 되고, 없는 값은 저장하지 않는다")
func recordingStartedAtStamp() throws {
    let recording = Recording(
        identity: TrackIdentity(sessionID: sessionID, memberID: memberID, recordingID: recordingID),
        state: .recording, lastActiveAt: time
    )

    let data = try FirestoreEncoding.recording(recording, stampStartedAt: true)

    #expect(isServerTimestamp(data["startedAt"]))
    #expect(isServerTimestamp(data["lastActiveAt"]))
    #expect(data["videoChunkCount"] == nil)
}
