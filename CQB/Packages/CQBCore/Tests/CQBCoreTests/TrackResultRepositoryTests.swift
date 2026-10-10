import Foundation
import Testing
import CQBCore
import CQBFixtures

private struct TrackContext {
    let store: InMemoryTrackResultStore
    let member: any TrackResultRepository
    let instructor: any TrackResultRepository
    let raw: ValidatedRawTrack
    let result: TrackResultDocument
    var identity: TrackIdentity { raw.document.identity }
    func request(_ document: TrackResultDocument? = nil, id: UUID = UUID()) throws -> PublishTrackResultRequest {
        .init(requestID: id, identity: identity, resultJSON: try TrackDocumentJSON.encode(document ?? result))
    }
}

private func trackContext(_ example: TrackContractFixture.Case = .normal, confirmed: Bool = true) async throws -> TrackContext {
    let map = try contractTrackMap()
    let raw = try TrackDocumentValidator.raw(TrackContractFixture.rawJSON(example), floorPlan: map)
    let store = InMemoryTrackResultStore()
    try await store.seedSession(id: raw.document.identity.sessionID, ownerUID: "instructor",
        members: [raw.document.identity.memberID: "member"], map: map)
    if confirmed { try await store.confirmRaw(raw) }
    return TrackContext(store: store, member: store.client(authenticatedUID: "member"),
        instructor: store.client(authenticatedUID: "instructor"), raw: raw,
        result: try TrackContractFixture.resultDocument(example))
}

struct TrackResultRepositoryTests {
    @Test func headingWarningSurvivesPublicationRetryAndInstructorRead() async throws {
        let c = try await trackContext()
        var result = c.result
        result.warnings = [.headingAmbiguous]
        let request = try c.request(result)
        await c.store.failOnce(at: .afterCommit)
        await #expect(throws: TrackRepositoryError.unavailable) { try await c.member.publishUsable(request) }
        let published = try await c.member.publishUsable(request)
        let selected = try await c.instructor.loadSelected(for: c.identity)
        #expect(published.bytes == request.resultJSON)
        #expect(selected?.document == result)
        #expect(selected?.document.status == .done)
        #expect(await c.store.counts.ready == 1)
    }

    @Test func rawMustBeConfirmedBeforePublication() async throws {
        let c = try await trackContext(confirmed: false)
        let request = try c.request()
        await #expect(throws: TrackRepositoryError.notReady) { try await c.member.publishUsable(request) }
        #expect(await c.store.counts.ready == 0)
        #expect(try await c.instructor.loadSelected(for: c.identity) == nil)
        try await c.store.confirmRaw(c.raw)
        let published = try await c.member.publishUsable(request)
        #expect(published.bytes == request.resultJSON)
        #expect(try await c.instructor.loadSelected(for: c.identity)?.document.resultID == c.result.resultID)
    }

    @Test func partialIsFirstSelectedWithoutOverwritingAnExistingSelection() async throws {
        let c = try await trackContext(.trackingGap)
        let first = try await c.member.publishUsable(c.request())
        #expect(first.document.status == .partial && !first.document.warnings.isEmpty)
        var next = c.result; next.resultID = UUID()
        _ = try await c.member.publishUsable(c.request(next))
        #expect(try await c.instructor.loadSelected(for: c.identity)?.document.resultID == first.document.resultID)
        #expect(try await c.instructor.load(resultID: next.resultID, for: c.identity).document == next)
    }

    @Test func stagedResultStaysHiddenAndSameRequestResumes() async throws {
        let c = try await trackContext()
        let request = try c.request()
        await c.store.failOnce(at: .afterStaging)
        await #expect(throws: TrackRepositoryError.unavailable) { try await c.member.publishUsable(request) }
        #expect(await c.store.counts.pending == 1)
        #expect(try await c.instructor.loadSelected(for: c.identity) == nil)
        await #expect(throws: TrackRepositoryError.notReady) {
            try await c.instructor.load(resultID: c.result.resultID, for: c.identity)
        }
        _ = try await c.member.publishUsable(request)
        #expect(await c.store.counts.pending == 0)
        #expect(await c.store.counts.ready == 1)
    }

    @Test func lostResponseRetryIsIdempotentAndChangedBytesConflict() async throws {
        let c = try await trackContext()
        let request = try c.request()
        await c.store.failOnce(at: .afterCommit)
        await #expect(throws: TrackRepositoryError.unavailable) { try await c.member.publishUsable(request) }
        let published = try await c.member.publishUsable(request)
        #expect(published.document.resultID == c.result.resultID)
        #expect(await c.store.counts.ready == 1)
        let changed = PublishTrackResultRequest(requestID: request.requestID, identity: c.identity,
            resultJSON: request.resultJSON + Data(" ".utf8))
        await #expect(throws: TrackRepositoryError.conflict) { try await c.member.publishUsable(changed) }
        await #expect(throws: TrackRepositoryError.conflict) { try await c.member.publishUsable(c.request()) }
    }

    @Test func concurrentRetriesPublishExactlyOneResult() async throws {
        let c = try await trackContext()
        let request = try c.request()
        async let first = c.member.publishUsable(request)
        async let second = c.member.publishUsable(request)
        let values = try await [first, second]
        #expect(values[0].sha256 == values[1].sha256)
        #expect(await c.store.counts.ready == 1)
    }

    @Test func failedReconstructionAndCancellationPreserveOldSelection() async throws {
        let c = try await trackContext()
        _ = try await c.member.publishUsable(c.request())
        var failed = c.result
        failed.resultID = UUID(); failed.status = .failed; failed.vertices = []
        failed.sampleCoverage = [.init(samples: .init(from: 0, through: 2), vertices: nil)]
        failed.unresolvedIntervals = [.init(from: 0.4, to: 2.4, bounds: .closed, reason: .unknown,
            samples: .init(from: 0, through: 2))]
        await #expect(throws: TrackRepositoryError.notUsable) { try await c.member.publishUsable(c.request(failed)) }
        let request = try c.request()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await c.member.publishUsable(request)
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {} catch { Issue.record("Unexpected: \(error)") }
        #expect(try await c.instructor.loadSelected(for: c.identity)?.document.resultID == c.result.resultID)
        #expect(await c.store.counts.ready == 1)
    }

    @Test func selectionCompareAndSetAndLostResponseRetryCannotRollbackNewSelection() async throws {
        let c = try await trackContext()
        _ = try await c.member.publishUsable(c.request())
        var second = c.result; second.resultID = UUID()
        var third = c.result; third.resultID = UUID()
        _ = try await c.member.publishUsable(c.request(second))
        _ = try await c.member.publishUsable(c.request(third))
        let request = SelectTrackResultRequest(requestID: UUID(), identity: c.identity,
            resultID: second.resultID, expectedSelectedResultID: c.result.resultID)
        await c.store.failOnce(at: .afterSelection)
        await #expect(throws: TrackRepositoryError.unavailable) { try await c.member.select(request) }
        await #expect(throws: TrackRepositoryError.conflict) {
            try await c.member.select(.init(requestID: UUID(), identity: c.identity,
                resultID: third.resultID, expectedSelectedResultID: c.result.resultID))
        }
        try await c.member.select(.init(requestID: UUID(), identity: c.identity,
            resultID: third.resultID, expectedSelectedResultID: second.resultID))
        try await c.member.select(request)
        #expect(try await c.instructor.loadSelected(for: c.identity)?.document.resultID == third.resultID)
    }

    @Test func permissionIsCheckedOnEveryReadWriteAndRetry() async throws {
        let c = try await trackContext()
        let request = try c.request()
        let outsider = c.store.client(authenticatedUID: "outsider")
        let anonymous = c.store.client(authenticatedUID: nil)
        await #expect(throws: TrackRepositoryError.unauthenticated) { try await anonymous.publishUsable(request) }
        await #expect(throws: TrackRepositoryError.permissionDenied) { try await outsider.publishUsable(request) }
        await #expect(throws: TrackRepositoryError.permissionDenied) { try await c.instructor.publishUsable(request) }
        _ = try await c.member.publishUsable(request)
        await #expect(throws: TrackRepositoryError.permissionDenied) { try await outsider.loadSelected(for: c.identity) }
        try await c.store.setMembers([:], sessionID: c.identity.sessionID)
        await #expect(throws: TrackRepositoryError.permissionDenied) { try await c.member.publishUsable(request) }
        await #expect(throws: TrackRepositoryError.permissionDenied) { try await c.member.loadSelected(for: c.identity) }
        #expect(try await c.instructor.loadSelected(for: c.identity)?.document.resultID == c.result.resultID)
    }

    @Test func mismatchedRawOrSessionCannotBeSubstituted() async throws {
        let c = try await trackContext()
        var raw = c.raw.document
        raw.samples[1].time = 1.1
        let validated = try TrackDocumentValidator.raw(TrackDocumentJSON.encode(raw), floorPlan: contractTrackMap())
        await #expect(throws: TrackRepositoryError.conflict) { try await c.store.confirmRaw(validated) }
        var result = c.result; result.sourceRawSHA256 = String(repeating: "0", count: 64)
        await #expect(throws: TrackValidationError.rawHashMismatch) { try await c.member.publishUsable(c.request(result)) }
        let counts = await c.store.counts
        #expect(counts.ready == 0 && counts.pending == 0)
    }

    @Test func transientReadFailureIsNotReportedAsNoSelection() async throws {
        let c = try await trackContext()
        _ = try await c.member.publishUsable(c.request())
        await c.store.failOnce(at: .beforeRead)
        await #expect(throws: TrackRepositoryError.unavailable) { try await c.instructor.loadSelected(for: c.identity) }
        #expect(try await c.instructor.loadSelected(for: c.identity)?.document.resultID == c.result.resultID)
    }

    @Test func simultaneousFirstPublicationsDoNotOverwriteEachOther() async throws {
        let c = try await trackContext()
        var second = c.result; second.resultID = UUID()
        let a = try c.request(), b = try c.request(second)
        async let one = c.member.publishUsable(a)
        async let two = c.member.publishUsable(b)
        let results = try await [one, two]
        let selected = try #require(try await c.instructor.loadSelected(for: c.identity))
        #expect(Set(results.map { $0.document.resultID }).contains(selected.document.resultID))
        _ = try await c.member.publishUsable(a)
        _ = try await c.member.publishUsable(b)
        #expect(try await c.instructor.loadSelected(for: c.identity)?.document.resultID == selected.document.resultID)
        #expect(await c.store.counts.ready == 2)
    }

    @Test func backendIsReleasedWhenClientsAreDropped() async throws {
        weak var released: InMemoryTrackResultStore?
        do {
            let c = try await trackContext()
            released = c.store
            _ = try await c.member.publishUsable(c.request())
        }
        #expect(released == nil)
    }
}
