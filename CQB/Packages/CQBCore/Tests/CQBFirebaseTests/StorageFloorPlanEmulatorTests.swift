import CQBCore
@testable import CQBFirebase
import CryptoKit
import Foundation
import Testing

@Test(
    "Storage Emulator에 도면 파일 3개를 올리고 같은 바이트로 재시도한다",
    .enabled(if: ProcessInfo.processInfo.environment["CQB_FIREBASE_EMULATOR_TESTS"] == "1")
)
func floorPlanUploadToEmulator() async throws {
    let navigation = Data(#"{"issue":46,"schemaVersion":1}"#.utf8)
    let files = FloorPlanFiles(
        imagePNG: Data([0x89, 0x50, 0x4E, 0x47]),
        navigationMapJSON: navigation,
        resolvedMask: Data([0, 1, 1, 0])
    )
    let reference = FloorPlanReference(
        floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000046")!,
        navigationSHA256: SHA256.hash(data: navigation).map { String(format: "%02x", $0) }.joined()
    )
    let token = try await anonymousEmulatorToken()
    let uploads = [
        (StoragePaths.floorPlanImage(reference), files.imagePNG, "image/png"),
        (StoragePaths.floorPlanMask(reference), files.resolvedMask, "application/octet-stream"),
        (StoragePaths.floorPlanNavigationMap(reference), files.navigationMapJSON, "application/json"),
    ]

    for (path, data, contentType) in uploads {
        try await ensureEmulatorObject(path: path, data: data, contentType: contentType, token: token)
    }
    // 같은 경로와 바이트를 다시 확인해 재시도 시 기존 불변 파일을 사용할 수 있음을 검증한다.
    for (path, data, contentType) in uploads {
        try await ensureEmulatorObject(path: path, data: data, contentType: contentType, token: token)
        let downloaded = try await emulatorObject(path: path, token: token)
        #expect(downloaded == data)
        let metadata = try await emulatorMetadata(path: path, token: token)
        #expect(metadata["contentType"] as? String == contentType)
    }
}

private func anonymousEmulatorToken() async throws -> String {
    var request = URLRequest(url: URL(
        string: "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator-api-key"
    )!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(#"{"returnSecureToken":true}"#.utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    try requireStatus(response, expected: 200)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = json["idToken"] as? String else {
        throw EmulatorTestError.invalidResponse
    }
    return token
}

private func ensureEmulatorObject(path: String, data: Data, contentType: String, token: String) async throws {
    do {
        let existing = try await emulatorObject(path: path, token: token)
        guard existing == data else { throw EmulatorTestError.contentMismatch(path) }
        return
    } catch EmulatorTestError.notFound {
        // Storage 규칙이 update를 막으므로 없는 파일에만 create 요청을 보낸다.
    }

    var components = URLComponents(string: "http://127.0.0.1:9199/v0/b/cqb-wffmst.firebasestorage.app/o")!
    components.queryItems = [
        URLQueryItem(name: "uploadType", value: "media"),
        URLQueryItem(name: "name", value: path),
    ]
    var request = authorizedRequest(url: components.url!, token: token)
    request.httpMethod = "POST"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    let (_, response) = try await URLSession.shared.data(for: request)
    try requireStatus(response, expected: 200)
}

private func emulatorObject(path: String, token: String) async throws -> Data {
    var components = URLComponents(string: metadataURL(path: path).absoluteString)!
    components.queryItems = [URLQueryItem(name: "alt", value: "media")]
    let (data, response) = try await URLSession.shared.data(
        for: authorizedRequest(url: components.url!, token: token)
    )
    if (response as? HTTPURLResponse)?.statusCode == 404 { throw EmulatorTestError.notFound }
    try requireStatus(response, expected: 200)
    return data
}

private func emulatorMetadata(path: String, token: String) async throws -> [String: Any] {
    let (data, response) = try await URLSession.shared.data(
        for: authorizedRequest(url: metadataURL(path: path), token: token)
    )
    try requireStatus(response, expected: 200)
    guard let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw EmulatorTestError.invalidResponse
    }
    return metadata
}

private func metadataURL(path: String) -> URL {
    let encoded = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    return URL(string: "http://127.0.0.1:9199/v0/b/cqb-wffmst.firebasestorage.app/o/\(encoded)")!
}

private func authorizedRequest(url: URL, token: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
}

private func requireStatus(_ response: URLResponse, expected: Int) throws {
    guard (response as? HTTPURLResponse)?.statusCode == expected else {
        throw EmulatorTestError.invalidResponse
    }
}

private enum EmulatorTestError: Error {
    case notFound
    case invalidResponse
    case contentMismatch(String)
}
