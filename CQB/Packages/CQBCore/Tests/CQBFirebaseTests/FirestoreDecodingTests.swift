import CQBCore
import FirebaseFirestore
import Foundation
import Testing
@testable import CQBFirebase

private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
private let memberID = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
private let recordingID = UUID(uuidString: "00000000-0000-0000-0000-000000000603")!
private let floorPlanID = UUID(uuidString: "00000000-0000-0000-0000-000000000604")!
private let time = Date(timeIntervalSince1970: 1_800_000_000)

@Test("pins 문서에서 세션 ID를 꺼낸다")
func sessionIDFromPin() throws {
    #expect(try FirestoreDecoding.sessionID(fromPin: ["sessionID": sessionID.uuidString]) == sessionID)
}

@Test("pins 문서의 세션 ID가 없거나 UUID가 아니면 invalidPin")
func invalidPin() {
    #expect(throws: FirestoreDecodingError.invalidPin) { try FirestoreDecoding.sessionID(fromPin: [:]) }
    #expect(throws: FirestoreDecodingError.invalidPin) {
        try FirestoreDecoding.sessionID(fromPin: ["sessionID": "not-a-uuid"])
    }
}

@Test("Session 문서를 읽고 instructorUid는 버린다")
func decodeSession() throws {
    let data: [String: Any] = [
        "id": sessionID.uuidString,
        "pin": "123456",
        "name": "오후 훈련",
        "status": "running",
        "startedAt": Timestamp(date: time),
        "floorPlan": ["floorPlanID": floorPlanID.uuidString, "navigationSHA256": "nav-sha"],
        "instructorUid": "instructor-uid",
    ]

    let session = try FirestoreDecoding.decode(Session.self, from: data)

    #expect(session.id == sessionID)
    #expect(session.pin == "123456")
    #expect(session.name == "오후 훈련")
    #expect(session.status == .running)
    #expect(session.startedAt == time)
    #expect(session.floorPlan == FloorPlanReference(floorPlanID: floorPlanID, navigationSHA256: "nav-sha"))
}

@Test("시작 전 Session은 startedAt 없이 읽힌다")
func decodeSessionWithoutStartedAt() throws {
    let data: [String: Any] = [
        "id": sessionID.uuidString,
        "pin": "123456",
        "name": "오후 훈련",
        "status": "waiting",
        "floorPlan": ["floorPlanID": floorPlanID.uuidString, "navigationSHA256": "nav-sha"],
    ]

    #expect(try FirestoreDecoding.decode(Session.self, from: data).startedAt == nil)
}

@Test("Member 문서를 읽고 uid와 pin은 버린다")
func decodeMember() throws {
    let data: [String: Any] = [
        "id": memberID.uuidString,
        "sessionID": sessionID.uuidString,
        "name": "대원 1",
        "isReady": true,
        "lastActiveAt": Timestamp(date: time),
        "uid": "member-uid",
        "pin": "123456",
    ]

    let member = try FirestoreDecoding.decode(Member.self, from: data)

    #expect(member.id == memberID)
    #expect(member.sessionID == sessionID)
    #expect(member.name == "대원 1")
    #expect(member.isReady)
    #expect(member.lastActiveAt == time)
}

@Test("Recording 문서를 읽는다")
func decodeRecording() throws {
    let data: [String: Any] = [
        "identity": [
            "sessionID": sessionID.uuidString,
            "memberID": memberID.uuidString,
            "recordingID": recordingID.uuidString,
        ],
        "state": "done",
        "startedAt": Timestamp(date: time),
        "lastActiveAt": Timestamp(date: time),
        "videoChunkCount": 7,
    ]

    let recording = try FirestoreDecoding.decode(Recording.self, from: data)

    #expect(recording.identity == TrackIdentity(sessionID: sessionID, memberID: memberID, recordingID: recordingID))
    #expect(recording.state == .done)
    #expect(recording.startedAt == time)
    #expect(recording.lastActiveAt == time)
    #expect(recording.videoChunkCount == 7)
}

@Test("모르는 상태 문자열이면 읽기에 실패한다")
func unknownStateFails() {
    let data: [String: Any] = [
        "identity": [
            "sessionID": sessionID.uuidString,
            "memberID": memberID.uuidString,
            "recordingID": recordingID.uuidString,
        ],
        "state": "uploading",
        "lastActiveAt": Timestamp(date: time),
    ]

    #expect(throws: (any Error).self) { try FirestoreDecoding.decode(Recording.self, from: data) }
}

@Test("저장용 변환 결과를 다시 읽으면 원래 값이 된다 (서버 시각 필드 제외)")
func encodeThenDecode() throws {
    let session = Session(
        id: sessionID, pin: "123456", name: "오후 훈련", status: .running, startedAt: time,
        floorPlan: FloorPlanReference(floorPlanID: floorPlanID, navigationSHA256: "nav-sha")
    )

    let decoded = try FirestoreDecoding.decode(
        Session.self,
        from: FirestoreEncoding.session(session, instructorUid: "instructor-uid")
    )

    #expect(decoded.id == session.id)
    #expect(decoded.pin == session.pin)
    #expect(decoded.name == session.name)
    #expect(decoded.status == session.status)
    #expect(decoded.startedAt == session.startedAt)
    #expect(decoded.floorPlan == session.floorPlan)
}
