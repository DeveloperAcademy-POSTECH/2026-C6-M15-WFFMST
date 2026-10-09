import CryptoKit
import Foundation
import Testing
import CQBFixtures

struct MinimalTrackFixtureTests {
    @Test func allReviewFilesAreBundledAsJSON() throws {
        #expect(MinimalTrackFixture.File.allCases.count == 6)
        for file in MinimalTrackFixture.File.allCases {
            let data = try MinimalTrackFixture.data(for: file)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["fixtureFormatVersion"] as? Int == 1)
        }
    }

    @Test func bundledRawBytesMatchHandRecordedHashes() throws {
        let data = try MinimalTrackFixture.data(for: .expectations)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try #require(json["cases"] as? [[String: Any]])
        #expect(cases.count == 4)
        for item in cases {
            let id = try #require(item["id"] as? String)
            let file = try #require(MinimalTrackFixture.File(rawValue: "\(id)-raw.json"))
            let bytes = try MinimalTrackFixture.data(for: file)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            #expect(hash == item["rawSHA256"] as? String)
        }
    }

    @Test func examplesRemainExplicitlySyntheticAndCoverRequiredStates() throws {
        let data = try MinimalTrackFixture.data(for: .expectations)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["algorithmExecuted"] as? Bool == false)
        #expect(json["status"] as? String == "review-sample-not-production-wire-schema")
        let cases = try #require(json["cases"] as? [[String: Any]])
        #expect(cases.compactMap { $0["status"] as? String } == ["done", "partial", "partial", "failed"])
        let gap = try #require(cases.first { $0["id"] as? String == "tracking-gap" })
        #expect(gap["validSampleCoverage"] as? Double == 1)
        #expect(gap["status"] as? String == "partial")
        let normal = try #require(cases.first { $0["id"] as? String == "normal" })
        #expect(normal["selectedCandidateIndex"] as? Int == 2)
    }
}
