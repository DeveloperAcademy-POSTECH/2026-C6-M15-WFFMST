import CQBCore
import XCTest
@testable import InstructorApp

final class AARSoundCandidateJudgeTests: XCTestCase {
    private let judge = AARSoundCandidateJudge.standard

    func testScoreAddsLabelMaximaAndCapsAtOne() {
        XCTAssertEqual(judge.score(of: candidate(1, gunfire: 0.2, artillery: 0.1)), 0.3, accuracy: 0.0001)
        XCTAssertEqual(judge.score(of: candidate(1, gunfire: 0.8, artillery: 0.7)), 1)
        XCTAssertEqual(judge.score(of: SoundCandidate(time: 1, peakLevelDBFS: -3, decaySeconds: 0.1, classifierScores: [:])), 0)
    }

    func testRejectsLowScoreShortDecayAndEcho() {
        let accepted = judge.accepted([
            candidate(1.0, gunfire: 0.9),                 // 총성
            candidate(1.3, gunfire: 0.9),                 // 0.45초 안: 같은 총성의 잔향
            candidate(1.51, gunfire: 0.9),                // 더블탭(0.51초 뒤)은 남는다
            candidate(3.0, gunfire: 0.2),                 // 점수 미달
            candidate(5.0, gunfire: 0.9, decay: 0.03),    // 폰 근처 충격음
            candidate(7.0, gunfire: 0.9, decay: nil),     // 잔향을 잴 수 없으면 잔향 조건을 쓰지 않는다
        ])

        XCTAssertEqual(accepted.map(\.time), [1.0, 1.51, 7.0])
    }

    func testRejectedCandidateDoesNotStartDebounce() {
        let accepted = judge.accepted([
            candidate(1.0, gunfire: 0.1),
            candidate(1.2, gunfire: 0.9),
        ])

        XCTAssertEqual(accepted.map(\.time), [1.2], "걸러진 후보 뒤의 총성은 잔향으로 보지 않는다")
    }

    func testThresholdBoundariesAreInclusive() {
        let accepted = judge.accepted([candidate(1, gunfire: 0.25, decay: 0.05)])

        XCTAssertEqual(accepted.map(\.time), [1])
    }

    private func candidate(_ time: Double, gunfire: Double, artillery: Double = 0, decay: Double? = 0.1) -> SoundCandidate {
        SoundCandidate(
            time: time,
            peakLevelDBFS: -3,
            decaySeconds: decay,
            classifierScores: ["gunshot_gunfire": gunfire, "artillery_fire": artillery]
        )
    }
}

final class RepositoryAARSoundCandidateLoaderTests: XCTestCase {
    private let identity = TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID())

    func testReturnsJudgedCandidateTimes() async throws {
        let document = SoundCandidateDocument(
            identity: identity,
            detector: SoundDetectorIdentity(name: "gunshot-combined", version: "713e743", settingsID: "onset-standard"),
            analyzedRanges: [SoundTimeRange(start: 0, end: 30)],
            candidates: [
                SoundCandidate(time: 4, peakLevelDBFS: -1, decaySeconds: 0.2, classifierScores: ["gunshot_gunfire": 0.9]),
                SoundCandidate(time: 9, peakLevelDBFS: -1, decaySeconds: 0.03, classifierScores: ["gunshot_gunfire": 0.9]),
                SoundCandidate(time: 12, peakLevelDBFS: -9, decaySeconds: 0.2, classifierScores: ["gunshot_gunfire": 0.05]),
            ]
        )
        let loader = RepositoryAARSoundCandidateLoader(repository: StubSoundCandidateRepository(result: .success(document)))

        let candidates = try await loader.candidates(for: identity)

        XCTAssertEqual(candidates, [AARSoundCandidate(recordingTime: 4)])
    }

    func testMissingFileOrUnknownVersionMeansNotAnalyzed() async throws {
        for error: any Error in [RepositoryError.notFound, SoundCandidateValidationError.unsupportedSchema(2)] {
            let loader = RepositoryAARSoundCandidateLoader(repository: StubSoundCandidateRepository(result: .failure(error)))

            let candidates = try await loader.candidates(for: identity)

            XCTAssertEqual(candidates, [], "\(error)")
        }
    }

    func testOtherFailuresAreThrown() async {
        let errors: [any Error] = [
            RepositoryError.integrityMismatch,
            SoundCandidateValidationError.invalidCandidates,
            URLError(.notConnectedToInternet),
        ]
        for error in errors {
            let loader = RepositoryAARSoundCandidateLoader(repository: StubSoundCandidateRepository(result: .failure(error)))
            do {
                _ = try await loader.candidates(for: identity)
                XCTFail("\(error)는 던져야 한다")
            } catch {}
        }
    }
}

private struct StubSoundCandidateRepository: SoundCandidateRepository {
    let result: Result<SoundCandidateDocument, any Error>

    func upload(_ document: SoundCandidateDocument) async throws {}
    func download(_ identity: TrackIdentity) async throws -> SoundCandidateDocument { try result.get() }
}
