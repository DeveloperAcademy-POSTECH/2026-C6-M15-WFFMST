import CQBCore
import Foundation
import Testing
@testable import CQBFirebase

private let identity = TrackIdentity(
    sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
    memberID: UUID(uuidString: "00000000-0000-0000-0000-000000000902")!,
    recordingID: UUID(uuidString: "00000000-0000-0000-0000-000000000903")!
)

private func encoded(_ document: SoundCandidateDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(document)
}

private func makeDocument(for identity: TrackIdentity) -> SoundCandidateDocument {
    SoundCandidateDocument(
        identity: identity,
        detector: SoundDetectorIdentity(name: "gunshot-combined", version: "0.3.0", settingsID: "candidate-low-v1"),
        analyzedRanges: [SoundTimeRange(start: 0, end: 60)],
        candidates: [SoundCandidate(time: 6.2, peakLevelDBFS: -1, decaySeconds: 0.12, classifierScores: ["gunshot_gunfire": 0.9])]
    )
}

@Test("받은 음향 후보가 요청한 기록의 것이면 그대로 돌려준다")
func soundCandidatesForRequestedRecording() throws {
    let document = makeDocument(for: identity)

    let decoded = try SoundCandidateFileValidation.decode(try encoded(document), for: identity)

    #expect(decoded == document)
}

@Test("다른 기록의 음향 후보를 받으면 무결성 오류다")
func soundCandidatesForOtherRecording() throws {
    let other = TrackIdentity(sessionID: identity.sessionID, memberID: identity.memberID, recordingID: UUID())
    let data = try encoded(makeDocument(for: other))

    #expect(throws: RepositoryError.integrityMismatch) {
        try SoundCandidateFileValidation.decode(data, for: identity)
    }
}
