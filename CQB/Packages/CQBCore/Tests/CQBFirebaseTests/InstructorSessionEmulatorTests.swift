import CQBCore
import Foundation
import Testing

@Test(
    "Firestore REST API로 세션·대원 준비 상태·PIN 회수의 저장 규칙을 검증한다",
    .enabled(if: ProcessInfo.processInfo.environment["CQB_FIREBASE_EMULATOR_TESTS"] == "1")
)
func instructorSessionReadinessOnEmulator() async throws {
    // REST 기반 계약·규칙 검증이다. 앱의 Firebase SDK 초기화와 연결은 시뮬레이터에서 별도로 확인한다.
    let instructor = try await emulatorIdentity()
    let member = try await emulatorIdentity()
    let session = Session(
        id: UUID(),
        pin: String(format: "%06d", Int.random(in: 0...999_999)),
        name: "Issue 49 Emulator 검증",
        status: .waiting,
        floorPlan: FloorPlanReference(
            floorPlanID: UUID(),
            navigationSHA256: String(repeating: "a", count: 64)
        )
    )

    try await createSessionOnEmulator(session, instructorUID: instructor.uid, token: instructor.token)
    let storedSession = try await emulatorDocument("sessions/\(session.id.uuidString)", token: instructor.token)
    let sessionFields = try fields(in: storedSession)
    #expect(stringValue(sessionFields["pin"]) == session.pin)
    #expect(stringValue(sessionFields["status"]) == SessionStatus.waiting.rawValue)
    let floorPlanFields = try fields(inMap: sessionFields["floorPlan"])
    #expect(stringValue(floorPlanFields["floorPlanID"]) == session.floorPlan.floorPlanID.uuidString)
    #expect(stringValue(floorPlanFields["navigationSHA256"]) == session.floorPlan.navigationSHA256)

    let memberID = UUID()
    try await writeMemberToEmulator(
        session: session,
        memberID: memberID,
        uid: member.uid,
        token: member.token,
        isReady: false
    )
    var memberFields = try await observedMemberFields(
        sessionID: session.id,
        token: instructor.token
    )
    #expect(stringValue(memberFields["name"]) == "에뮬레이터 대원")
    #expect(booleanValue(memberFields["isReady"]) == false)

    try await writeMemberToEmulator(
        session: session,
        memberID: memberID,
        uid: member.uid,
        token: member.token,
        isReady: true
    )
    memberFields = try await observedMemberFields(sessionID: session.id, token: instructor.token)
    #expect(booleanValue(memberFields["isReady"]) == true)

    try await endSessionOnEmulator(session, token: instructor.token)
    let endedSession = try await emulatorDocument("sessions/\(session.id.uuidString)", token: instructor.token)
    #expect(stringValue(try fields(in: endedSession)["status"]) == SessionStatus.ended.rawValue)
    await #expect(throws: InstructorEmulatorTestError.notFound) {
        try await emulatorDocument("pins/\(session.pin)", token: member.token)
    }
}

private func emulatorIdentity() async throws -> (uid: String, token: String) {
    var request = URLRequest(url: URL(
        string: "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator-api-key"
    )!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(#"{"returnSecureToken":true}"#.utf8)
    let json = try await emulatorJSON(request, expectedStatus: 200)
    guard let uid = json["localId"] as? String,
          let token = json["idToken"] as? String else {
        throw InstructorEmulatorTestError.invalidResponse
    }
    return (uid, token)
}

@Test(
    "Firestore REST API로 훈련 서버 시각·종료와 대원별 기록 상태 권한을 검증한다",
    .enabled(if: ProcessInfo.processInfo.environment["CQB_FIREBASE_EMULATOR_TESTS"] == "1")
)
func instructorTrainingLifecycleOnEmulator() async throws {
    // #47 업로드 구현과 별개인 상태 계약 검사다. 실제 SDK 구독·화면 전환은 앱에서 별도 검증한다.
    let instructor = try await emulatorIdentity()
    let first = try await emulatorIdentity()
    let second = try await emulatorIdentity()
    let session = Session(
        id: UUID(), pin: String(format: "%06d", Int.random(in: 0...999_999)), name: "Issue 56 Emulator 검증",
        status: .waiting, floorPlan: FloorPlanReference(floorPlanID: UUID(), navigationSHA256: String(repeating: "b", count: 64))
    )
    try await createSessionOnEmulator(session, instructorUID: instructor.uid, token: instructor.token)
    let firstID = UUID()
    let secondID = UUID()
    try await writeMemberToEmulator(session: session, memberID: firstID, uid: first.uid, token: first.token, isReady: true)
    try await writeMemberToEmulator(session: session, memberID: secondID, uid: second.uid, token: second.token, isReady: true)

    try await commit(writes: [[
        "update": ["name": documentName("sessions/\(session.id.uuidString)"), "fields": ["status": stringField("running")]],
        "updateMask": ["fieldPaths": ["status"]],
        "updateTransforms": [["fieldPath": "startedAt", "setToServerValue": "REQUEST_TIME"]],
    ]], token: instructor.token)
    let running = try fields(in: await emulatorDocument("sessions/\(session.id.uuidString)", token: instructor.token))
    #expect(stringValue(running["status"]) == "running")
    let startedAt = (running["startedAt"] as? [String: Any])?["timestampValue"] as? String
    #expect(startedAt != nil)
    let empty = try await emulatorCollection("sessions/\(session.id.uuidString)/recordings", token: instructor.token)
    #expect((empty["documents"] as? [[String: Any]] ?? []).isEmpty)

    let firstRecording = UUID()
    let secondRecording = UUID()
    try await writeLifecycleRecord(session.id, firstID, firstRecording, state: .recording, token: first.token, isNew: true)
    try await writeLifecycleRecord(session.id, secondID, secondRecording, state: .recording, token: second.token, isNew: true)
    try await endSessionOnEmulator(session, token: instructor.token)
    let ended = try fields(in: await emulatorDocument("sessions/\(session.id.uuidString)", token: instructor.token))
    #expect(stringValue(ended["status"]) == "ended")
    #expect((ended["startedAt"] as? [String: Any])?["timestampValue"] as? String == startedAt)
    await #expect(throws: InstructorEmulatorTestError.notFound) {
        try await emulatorDocument("pins/\(session.pin)", token: first.token)
    }

    // 세션 종료 후에도 대원은 본인 기록의 처리·업로드 결과를 보고할 수 있어야 한다.
    try await writeLifecycleRecord(session.id, firstID, firstRecording, state: .finishing, token: first.token)
    let firstPath = "sessions/\(session.id.uuidString)/recordings/\(firstRecording.uuidString)"
    let finishing = try fields(in: await emulatorDocument(firstPath, token: instructor.token))
    #expect(stringValue(finishing["state"]) == "finishing")

    // 교관이 대원 기록을 완료 처리하는 우회 경로는 허용하지 않는다.
    var forbidden = authorizedRequest(url: URL(string: "http://127.0.0.1:8080/v1/projects/cqb-wffmst/databases/(default)/documents:commit")!, token: instructor.token)
    forbidden.httpMethod = "POST"
    forbidden.setValue("application/json", forHTTPHeaderField: "Content-Type")
    forbidden.httpBody = try JSONSerialization.data(withJSONObject: ["writes": [[
        "update": ["name": documentName(firstPath), "fields": ["state": stringField("done")]],
        "updateMask": ["fieldPaths": ["state"]],
        "updateTransforms": [["fieldPath": "lastActiveAt", "setToServerValue": "REQUEST_TIME"]],
    ]]])
    _ = try await emulatorJSON(forbidden, expectedStatus: 403)

    try await writeLifecycleRecord(session.id, firstID, firstRecording, state: .done, token: first.token)
    try await writeLifecycleRecord(session.id, secondID, secondRecording, state: .failed, token: second.token)
    let result = try await emulatorCollection("sessions/\(session.id.uuidString)/recordings", token: instructor.token)
    let documents = try #require(result["documents"] as? [[String: Any]])
    #expect(documents.count == 2)
    let states = try documents.compactMap { stringValue(try fields(in: $0)["state"]) }.sorted()
    #expect(states == ["done", "failed"])
}

private func writeLifecycleRecord(
    _ sessionID: UUID, _ memberID: UUID, _ recordingID: UUID,
    state: RecordingState, token: String, isNew: Bool = false
) async throws {
    var transforms: [[String: Any]] = [["fieldPath": "lastActiveAt", "setToServerValue": "REQUEST_TIME"]]
    if isNew { transforms.append(["fieldPath": "startedAt", "setToServerValue": "REQUEST_TIME"]) }
    try await commit(writes: [[
        "update": [
            "name": documentName("sessions/\(sessionID.uuidString)/recordings/\(recordingID.uuidString)"),
            "fields": [
                "identity": ["mapValue": ["fields": [
                    "sessionID": stringField(sessionID.uuidString), "memberID": stringField(memberID.uuidString),
                    "recordingID": stringField(recordingID.uuidString),
                ]]],
                "state": stringField(state.rawValue),
            ],
        ],
        "updateMask": ["fieldPaths": ["identity", "state"]],
        "updateTransforms": transforms,
    ]], token: token)
}

private func createSessionOnEmulator(
    _ session: Session,
    instructorUID: String,
    token: String
) async throws {
    let sessionName = documentName("sessions/\(session.id.uuidString)")
    let pinName = documentName("pins/\(session.pin)")
    let writes: [[String: Any]] = [
        ["update": [
            "name": sessionName,
            "fields": [
                "id": stringField(session.id.uuidString),
                "pin": stringField(session.pin),
                "name": stringField(session.name),
                "status": stringField(session.status.rawValue),
                "floorPlan": ["mapValue": ["fields": [
                    "floorPlanID": stringField(session.floorPlan.floorPlanID.uuidString),
                    "navigationSHA256": stringField(session.floorPlan.navigationSHA256),
                ]]],
                "instructorUid": stringField(instructorUID),
            ],
        ]],
        ["update": [
            "name": pinName,
            "fields": ["sessionID": stringField(session.id.uuidString)],
        ]],
    ]
    try await commit(writes: writes, token: token)
}

private func writeMemberToEmulator(
    session: Session,
    memberID: UUID,
    uid: String,
    token: String,
    isReady: Bool
) async throws {
    let writes: [[String: Any]] = [[
        "update": [
            "name": documentName("sessions/\(session.id.uuidString)/members/\(memberID.uuidString)"),
            "fields": [
                "id": stringField(memberID.uuidString),
                "sessionID": stringField(session.id.uuidString),
                "name": stringField("에뮬레이터 대원"),
                "isReady": ["booleanValue": isReady],
                "uid": stringField(uid),
                "pin": stringField(session.pin),
            ],
        ],
        "updateTransforms": [[
            "fieldPath": "lastActiveAt",
            "setToServerValue": "REQUEST_TIME",
        ]],
    ]]
    try await commit(writes: writes, token: token)
}

private func observedMemberFields(sessionID: UUID, token: String) async throws -> [String: Any] {
    let json = try await emulatorCollection("sessions/\(sessionID.uuidString)/members", token: token)
    guard let documents = json["documents"] as? [[String: Any]], documents.count == 1 else {
        throw InstructorEmulatorTestError.invalidResponse
    }
    return try fields(in: documents[0])
}

private func endSessionOnEmulator(
    _ session: Session,
    token: String
) async throws {
    let writes: [[String: Any]] = [
        [
            "update": [
                "name": documentName("sessions/\(session.id.uuidString)"),
                "fields": ["status": stringField(SessionStatus.ended.rawValue)],
            ],
            "updateMask": ["fieldPaths": ["status"]],
        ],
        ["delete": documentName("pins/\(session.pin)")],
    ]
    try await commit(writes: writes, token: token)
}

private func commit(writes: [[String: Any]], token: String) async throws {
    var request = authorizedRequest(
        url: URL(string: "http://127.0.0.1:8080/v1/projects/cqb-wffmst/databases/(default)/documents:commit")!,
        token: token
    )
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["writes": writes])
    _ = try await emulatorJSON(request, expectedStatus: 200)
}

private func emulatorDocument(_ path: String, token: String) async throws -> [String: Any] {
    let request = authorizedRequest(url: documentURL(path), token: token)
    return try await emulatorJSON(request, expectedStatus: 200)
}

private func emulatorCollection(_ path: String, token: String) async throws -> [String: Any] {
    let request = authorizedRequest(url: documentURL(path), token: token)
    return try await emulatorJSON(request, expectedStatus: 200)
}

private func emulatorJSON(_ request: URLRequest, expectedStatus: Int) async throws -> [String: Any] {
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode
    if status == 404 { throw InstructorEmulatorTestError.notFound }
    guard status == expectedStatus,
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw InstructorEmulatorTestError.requestFailed(status, String(decoding: data, as: UTF8.self))
    }
    return json
}

private func authorizedRequest(url: URL, token: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
}

private func documentURL(_ path: String) -> URL {
    URL(string: "http://127.0.0.1:8080/v1/projects/cqb-wffmst/databases/(default)/documents/\(path)")!
}

private func documentName(_ path: String) -> String {
    "projects/cqb-wffmst/databases/(default)/documents/\(path)"
}

private func stringField(_ value: String) -> [String: String] {
    ["stringValue": value]
}

private func fields(in document: [String: Any]) throws -> [String: Any] {
    guard let result = document["fields"] as? [String: Any] else {
        throw InstructorEmulatorTestError.invalidResponse
    }
    return result
}

private func fields(inMap value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any],
          let map = value["mapValue"] as? [String: Any],
          let result = map["fields"] as? [String: Any] else {
        throw InstructorEmulatorTestError.invalidResponse
    }
    return result
}

private func stringValue(_ value: Any?) -> String? {
    (value as? [String: Any])?["stringValue"] as? String
}

private func booleanValue(_ value: Any?) -> Bool? {
    (value as? [String: Any])?["booleanValue"] as? Bool
}

private enum InstructorEmulatorTestError: Error, Equatable {
    case notFound
    case invalidResponse
    case requestFailed(Int?, String)
}
