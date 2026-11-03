import Foundation
import Testing
@testable import CQBCore

private let identity = TrackIdentity(
    sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000169")!,
    memberID: UUID(uuidString: "00000000-0000-0000-0000-000000000170")!,
    recordingID: UUID(uuidString: "00000000-0000-0000-0000-000000000171")!
)

private func makeDocument() -> SoundCandidateDocument {
    SoundCandidateDocument(
        identity: identity,
        detector: SoundDetectorIdentity(name: "gunshot-combined", version: "0.3.0", settingsID: "candidate-low-v1"),
        analyzedRanges: [SoundTimeRange(start: 0, end: 120), SoundTimeRange(start: 135, end: 300)],
        candidates: [
            SoundCandidate(
                time: 12.345,
                peakLevelDBFS: -1.2,
                decaySeconds: 0.13,
                classifierScores: ["gunshot_gunfire": 0.82, "artillery_fire": 0.11]
            ),
            SoundCandidate(time: 299.99, peakLevelDBFS: -6, decaySeconds: nil, classifierScores: [:]),
        ]
    )
}

@Test("SoundCandidateDocument가 음향 후보 계약을 Codable 왕복한다")
func soundCandidateDocumentCodableRoundTrip() throws {
    let document = makeDocument()

    let decoded = try codableRoundTrip(document)

    #expect(decoded == document)
    #expect(decoded.schemaVersion == SoundCandidateDocument.currentSchemaVersion)
    #expect(decoded.candidates.map(\.time) == [12.345, 299.99])
}

@Test("음향 후보 JSON은 계약 문서의 필드 이름을 쓴다")
func soundCandidateDocumentJSONShape() throws {
    let json = try encodedJSONObject(makeDocument())

    #expect(Set(json.keys) == ["schemaVersion", "identity", "detector", "analyzedRanges", "candidates"])
    let detector = try #require(json["detector"] as? [String: Any])
    #expect(Set(detector.keys) == ["name", "version", "settingsID"])
    let ranges = try #require(json["analyzedRanges"] as? [[String: Any]])
    #expect(Set(ranges[0].keys) == ["start", "end"])
    let candidates = try #require(json["candidates"] as? [[String: Any]])
    #expect(Set(candidates[0].keys) == ["time", "peakLevelDBFS", "decaySeconds", "classifierScores"])
}

@Test("잴 수 없는 잔향은 빠지고, 없는 키는 nil로 읽는다")
func soundCandidateWithoutDecay() throws {
    let json = try encodedJSONObject(makeDocument())
    let candidates = try #require(json["candidates"] as? [[String: Any]])
    #expect(candidates[1]["decaySeconds"] == nil)

    let data = Data(#"{"time":1,"peakLevelDBFS":-3,"classifierScores":{}}"#.utf8)
    let candidate = try JSONDecoder().decode(SoundCandidate.self, from: data)
    #expect(candidate.decaySeconds == nil)
}

@Test("모르는 분류기 점수 키와 추가 필드가 있어도 읽는다")
func soundCandidateIgnoresUnknownValues() throws {
    let data = Data(#"{"time":1,"peakLevelDBFS":-3,"decaySeconds":0.1,"classifierScores":{"future_label":0.4},"spectralFlux":2.5}"#.utf8)

    let candidate = try JSONDecoder().decode(SoundCandidate.self, from: data)

    #expect(candidate.classifierScores["future_label"] == 0.4)
}

@Test("분석 구간은 양 끝을 포함한다")
func soundTimeRangeContains() {
    let range = SoundTimeRange(start: 10, end: 20)

    #expect(range.contains(10))
    #expect(range.contains(20))
    #expect(!range.contains(20.01))
}
