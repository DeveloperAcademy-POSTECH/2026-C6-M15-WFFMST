import Foundation
import Testing
import CQBCore
import CQBFixtures
import CQBImageIO

private func registration(requestID: UUID = UUID(), name: String = "훈련장 A",
                          newIdentity: Bool = false) throws -> RegisterFloorPlanRequest {
    var json = try NormalFloorPlanFixture.data(for: .manifest)
    var reference = try JSONDecoder().decode(FloorPlanReference.self, from: NormalFloorPlanFixture.data(for: .reference))
    if newIdentity {
        let floorID = UUID(), revisionID = UUID()
        var object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        object["floorPlanID"] = floorID.uuidString.lowercased()
        object["revisionID"] = revisionID.uuidString.lowercased()
        json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        reference = FloorPlanReference(floorPlanID: floorID, revisionID: revisionID,
                                      navigationSHA256: FloorPlanJSON.sha256(json))
    }
    return RegisterFloorPlanRequest(requestID: requestID, name: name, reference: reference,
        files: FloorPlanFiles(imagePNG: try NormalFloorPlanFixture.data(for: .image),
                             navigationMapJSON: json, resolvedMask: try NormalFloorPlanFixture.data(for: .mask)))
}

private func backend() -> InMemoryFloorPlanStore {
    InMemoryFloorPlanStore(imageValidator: PNGFloorPlanImageValidator())
}

@Suite struct FloorPlanPageCacheTests {
    private func populate(_ client: InMemoryFloorPlanClient, count: Int) async throws -> [FloorPlanSummary] {
        var summaries: [FloorPlanSummary] = []
        for _ in 0..<count {
            summaries.append(try await client.register(registration(newIdentity: true)))
        }
        return summaries.sorted { $0.reference.floorPlanID.uuidString < $1.reference.floorPlanID.uuidString }
    }

    @Test func repeatedCursorReusesSnapshotAndNextCursor() async throws {
        let store = backend(), owner = store.client(authenticatedUID: "owner")
        let expected = try await populate(owner, count: 3)
        let first = try await owner.list(pageSize: 1, cursor: nil)
        let cursor = try #require(first.nextCursor)
        var nextCursors: Set<String> = []
        for _ in 0..<100 {
            let page = try await owner.list(pageSize: 1, cursor: cursor)
            #expect(page.items == [expected[1]])
            nextCursors.insert(try #require(page.nextCursor))
        }
        let counts = await store.pageCacheCounts
        print("Page cache retry evidence: 100 retries, snapshots=\(counts.snapshots), summaries=\(counts.summaries), distinct next cursors=\(nextCursors.count)")
        #expect(counts.snapshots == 1)
        #expect(counts.summaries == 3)
        #expect(nextCursors.count == 1)
        // A terminal page remains retryable; reading it must not discard the snapshot.
        let terminalCursor = try #require(nextCursors.first)
        for _ in 0..<2 {
            let last = try await owner.list(pageSize: 1, cursor: terminalCursor)
            #expect(last.items == [expected[2]])
            #expect(last.nextCursor == nil)
        }
        #expect(await store.pageCacheCounts.snapshots == 1)
        #expect(await store.pageCacheCounts.summaries == 3)
    }

    @Test func changingPageSizeTraversesOneSnapshotWithoutTailCopies() async throws {
        let store = backend(), owner = store.client(authenticatedUID: "owner")
        let expected = try await populate(owner, count: 12)
        var cursor: String?
        var actual: [FloorPlanSummary] = []
        for pageSize in [1, 2, 3, 100] {
            let page = try await owner.list(pageSize: pageSize, cursor: cursor)
            actual += page.items
            cursor = page.nextCursor
        }
        #expect(cursor == nil)
        #expect(actual == expected)
        let counts = await store.pageCacheCounts
        print("Page cache traversal evidence: 12 maps, snapshots=\(counts.snapshots), summaries=\(counts.summaries)")
        #expect(counts.snapshots == 1)
        #expect(counts.summaries == 12)
    }

    @Test func freshQueriesAreBoundedAndEvictedCursorsCanRestart() async throws {
        let store = backend(), owner = store.client(authenticatedUID: "owner")
        let expected = try await populate(owner, count: 3)
        var cursors: [String] = []
        for _ in 0..<100 {
            let page = try await owner.list(pageSize: 1, cursor: nil)
            cursors.append(try #require(page.nextCursor))
        }
        let limit = InMemoryFloorPlanStore.maximumPageSnapshots
        let counts = await store.pageCacheCounts
        print("Page cache refresh evidence: 100 fresh queries, snapshots=\(counts.snapshots), summaries=\(counts.summaries), limit=\(limit)")
        #expect(counts.snapshots == limit)
        #expect(counts.summaries == limit * expected.count)
        for cursor in [cursors[0], cursors[cursors.count - limit - 1]] {
            await #expect(throws: FloorPlanRepositoryError.invalidCursor) {
                try await owner.list(pageSize: 1, cursor: cursor)
            }
        }
        // All retained snapshots, including the oldest, still work.
        for cursor in cursors.suffix(limit) {
            #expect(try await owner.list(pageSize: 100, cursor: cursor).items == Array(expected.dropFirst()))
        }
        let oldest = cursors[cursors.count - limit]
        // Refreshing the oldest snapshot must not renew FIFO retention as LRU would.
        #expect(try await owner.list(pageSize: 100, cursor: oldest).items == Array(expected.dropFirst()))
        let restarted = try await owner.list(pageSize: 1, cursor: nil)
        #expect(restarted.items == [expected[0]])
        #expect(restarted.nextCursor != nil)
        #expect(await store.pageCacheCounts.snapshots == limit)
        await #expect(throws: FloorPlanRepositoryError.invalidCursor) {
            try await owner.list(pageSize: 1, cursor: oldest)
        }
        // Eviction affects only list snapshots, not the registered maps.
        #expect(await store.counts.ready == expected.count)
        #expect(try await owner.loadOwned(expected[0].reference).reference == expected[0].reference)
    }

    @Test func snapshotLimitIsGlobalAndDoesNotMixOwners() async throws {
        let store = backend()
        let a = store.client(authenticatedUID: "owner-a"), b = store.client(authenticatedUID: "owner-b")
        let mapsA = try await populate(a, count: 3), mapsB = try await populate(b, count: 2)
        var latestA: String?, latestB: String?
        for _ in 0..<20 {
            let pageA = try await a.list(pageSize: 1, cursor: nil)
            let pageB = try await b.list(pageSize: 1, cursor: nil)
            #expect(pageA.items == [mapsA[0]])
            #expect(pageB.items == [mapsB[0]])
            let nextA = try #require(pageA.nextCursor), nextB = try #require(pageB.nextCursor)
            latestA = nextA
            latestB = nextB
        }
        let cursorA = try #require(latestA), cursorB = try #require(latestB)
        #expect(await store.pageCacheCounts.snapshots == 16)
        #expect(await store.pageCacheCounts.summaries == 8 * 3 + 8 * 2)
        #expect(try await a.list(pageSize: 100, cursor: cursorA).items == Array(mapsA.dropFirst()))
        #expect(try await b.list(pageSize: 100, cursor: cursorB).items == Array(mapsB.dropFirst()))
        await #expect(throws: FloorPlanRepositoryError.invalidCursor) { try await b.list(pageSize: 1, cursor: cursorA) }
        await #expect(throws: FloorPlanRepositoryError.invalidCursor) { try await a.list(pageSize: 1, cursor: cursorB) }
    }

    @Test func snapshotStaysFrozenAcrossPendingAndSuccessfulRegistration() async throws {
        let store = backend(), owner = store.client(authenticatedUID: "owner")
        let original = try await populate(owner, count: 3)
        let first = try await owner.list(pageSize: 1, cursor: nil)
        let cursor = try #require(first.nextCursor)
        let newMap = try registration(newIdentity: true)
        await store.failOnce(at: .afterStagingRegistration)
        await #expect(throws: FloorPlanRepositoryError.unavailable) { try await owner.register(newMap) }
        #expect(try await owner.list(pageSize: 100, cursor: nil).items == original)
        _ = try await owner.register(newMap)
        let oldTail = try await owner.list(pageSize: 100, cursor: cursor)
        #expect(first.items + oldTail.items == original)
        #expect(oldTail.nextCursor == nil)
        let fresh = try await owner.list(pageSize: 100, cursor: nil)
        #expect(Set(fresh.items.map(\.reference)) == Set(original.map(\.reference) + [newMap.reference]))
        #expect(await store.pageCacheCounts.snapshots == 1)
    }

    @Test func invalidRequestsAndForeignCursorsCannotChangeCache() async throws {
        let store = backend(), owner = store.client(authenticatedUID: "owner")
        _ = try await populate(owner, count: 3)
        let first = try await owner.list(pageSize: 1, cursor: nil)
        let cursor = try #require(first.nextCursor)
        let counts = await store.pageCacheCounts
        await #expect(throws: FloorPlanRepositoryError.invalidCursor) {
            try await store.client(authenticatedUID: "other").list(pageSize: 1, cursor: cursor)
        }
        let otherStore = backend()
        await #expect(throws: FloorPlanRepositoryError.invalidCursor) {
            try await otherStore.client(authenticatedUID: "owner").list(pageSize: 1, cursor: cursor)
        }
        await #expect(throws: FloorPlanRepositoryError.unauthenticated) {
            try await store.client(authenticatedUID: nil).list(pageSize: 1, cursor: cursor)
        }
        // Backend codec robustness only: app callers must treat cursors as opaque.
        let id = String(cursor.split(separator: ":")[0])
        let invalid = ["", "unknown", cursor + ":extra", "\(id):-1", "\(id):0", "\(id):3",
                       "\(id):\(Int.max)", "\(id):9999999999999999999999999999999",
                       "\(id):+1", "\(id):01", "\(id):", ":1"]
        for value in invalid {
            await #expect(throws: FloorPlanRepositoryError.invalidCursor) {
                try await owner.list(pageSize: 1, cursor: value)
            }
        }
        for size in [0, -1, 101, Int.max] {
            await #expect(throws: FloorPlanRepositoryError.invalidRequest) {
                try await owner.list(pageSize: size, cursor: cursor)
            }
        }
        let after = await store.pageCacheCounts
        #expect(after.snapshots == counts.snapshots && after.summaries == counts.summaries)
    }

    @Test func failuresAndCancellationDoNotAllocateOrEvictSnapshots() async throws {
        let store = backend(), owner = store.client(authenticatedUID: "owner")
        let expected = try await populate(owner, count: 3)
        var firstCursor: String?
        for _ in 0..<InMemoryFloorPlanStore.maximumPageSnapshots {
            let page = try await owner.list(pageSize: 1, cursor: nil)
            if firstCursor == nil { firstCursor = page.nextCursor }
        }
        let cursor = try #require(firstCursor)
        let before = await store.pageCacheCounts
        for requestedCursor: String? in [nil, cursor] {
            await store.failOnce(at: .beforeRead)
            await #expect(throws: FloorPlanRepositoryError.unavailable) {
                try await owner.list(pageSize: 1, cursor: requestedCursor)
            }
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await owner.list(pageSize: 1, cursor: requestedCursor)
            }
            do { _ = try await task.value; Issue.record("Expected CancellationError") }
            catch is CancellationError { }
            catch { Issue.record("Unexpected error: \(error)") }
        }
        let after = await store.pageCacheCounts
        #expect(after.snapshots == before.snapshots && after.summaries == before.summaries)
        #expect(try await owner.list(pageSize: 100, cursor: cursor).items == Array(expected.dropFirst()))
    }

    @Test func emptyAndSinglePageListsDoNotAllocateSnapshots() async throws {
        let store = backend(), owner = store.client(authenticatedUID: "owner")
        let empty = try await owner.list(pageSize: 1, cursor: nil)
        #expect(empty.items.isEmpty && empty.nextCursor == nil)
        let expected = try await populate(owner, count: 1)
        for _ in 0..<100 {
            let page = try await owner.list(pageSize: 1, cursor: nil)
            #expect(page.items == expected && page.nextCursor == nil)
        }
        #expect(await store.pageCacheCounts.snapshots == 0)
        #expect(await store.pageCacheCounts.summaries == 0)
    }

    @Test func concurrentCursorRetriesDoNotAccumulateSnapshots() async throws {
        let store = backend(), owner = store.client(authenticatedUID: "owner")
        let expected = try await populate(owner, count: 3)
        let first = try await owner.list(pageSize: 1, cursor: nil)
        let cursor = try #require(first.nextCursor)
        let pages = try await withThrowingTaskGroup(of: FloorPlanPage.self) { group in
            for _ in 0..<100 { group.addTask { try await owner.list(pageSize: 1, cursor: cursor) } }
            var pages: [FloorPlanPage] = []
            for try await page in group { pages.append(page) }
            return pages
        }
        #expect(pages.count == 100)
        #expect(pages.allSatisfy { $0.items == [expected[1]] && $0.nextCursor != nil })
        #expect(Set(pages.compactMap(\.nextCursor)).count == 1)
        #expect(await store.pageCacheCounts.snapshots == 1)
        #expect(await store.pageCacheCounts.summaries == 3)
    }

    @Test func populatedCacheDoesNotRetainBackendAfterClientsAreReleased() async throws {
        weak var released: InMemoryFloorPlanStore?
        func exercise() async throws {
            let store = backend(), owner = store.client(authenticatedUID: "owner")
            released = store
            _ = try await populate(owner, count: 3)
            let first = try await owner.list(pageSize: 1, cursor: nil)
            let cursor = try #require(first.nextCursor)
            _ = try await owner.list(pageSize: 1, cursor: cursor)
            #expect(await store.pageCacheCounts.snapshots > 0)
        }
        try await exercise()
        #expect(released == nil)
    }
}

@Test func repositoryRegistersWithoutSessionAndSharesOneMapAcrossTwoSessions() async throws {
    let store = backend()
    let owner = store.client(authenticatedUID: "owner-a")
    let repo: any FloorPlanRepository = owner
    let creator: any FloorPlanSessionCreating = owner
    let request = try registration()
    let summary = try await repo.register(request)
    #expect(summary.reference == request.reference)
    #expect(await store.counts.sessions == 0)
    #expect(try await repo.list(pageSize: 20, cursor: nil).items == [summary])
    let s1 = try await creator.createSession(.init(requestID: UUID(), name: "훈련 1", floorPlan: summary.reference))
    let s2 = try await creator.createSession(.init(requestID: UUID(), name: "훈련 2", floorPlan: summary.reference))
    #expect(s1.sessionID != s2.sessionID && s1.floorPlan == s2.floorPlan)
    try await store.setParticipants(["member-a"], sessionID: s1.sessionID)
    try await store.setParticipants(["member-b"], sessionID: s2.sessionID)
    for (uid, session) in [("member-a", s1), ("member-b", s2)] {
        let map = try await store.client(authenticatedUID: uid).loadForSession(session.sessionID, expectedReference: session.floorPlan)
        #expect(map.files.navigationMapJSON == request.files.navigationMapJSON)
        #expect(map.pixelsPerMeter == 20)
        #expect(map.cell(at: ImagePoint(x: 100, y: 120))?.index == 30050)
        #expect(map.isBlocked(at: ImagePoint(x: 220, y: 120)))
    }
    // Reusing one map does not share participation between the two sessions.
    await #expect(throws: FloorPlanRepositoryError.permissionDenied) {
        try await store.client(authenticatedUID: "member-a").loadForSession(s2.sessionID, expectedReference: s2.floorPlan)
    }
    let counts = await store.counts
    #expect(counts.ready == 1 && counts.pending == 0 && counts.sessions == 2)
}

@Test func repositoryEnforcesOwnerAndVerifiedSessionMembershipOnEveryRead() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    let other = store.client(authenticatedUID: "other")
    _ = try await owner.register(request)
    let session = try await owner.createSession(.init(requestID: UUID(), name: "훈련", floorPlan: request.reference))
    #expect(try await other.list(pageSize: 20, cursor: nil).items.isEmpty)
    await #expect(throws: FloorPlanRepositoryError.permissionDenied) { try await other.loadOwned(request.reference) }
    await #expect(throws: FloorPlanRepositoryError.permissionDenied) {
        try await other.createSession(.init(requestID: UUID(), name: "훈련", floorPlan: request.reference))
    }
    await #expect(throws: FloorPlanRepositoryError.permissionDenied) {
        try await other.loadForSession(session.sessionID, expectedReference: request.reference)
    }
    try await store.setParticipants(["other"], sessionID: session.sessionID)
    #expect(try await other.loadForSession(session.sessionID, expectedReference: request.reference).reference == request.reference)
    // Membership grants session access only, never the owner's library endpoint.
    await #expect(throws: FloorPlanRepositoryError.permissionDenied) { try await other.loadOwned(request.reference) }
    try await store.setParticipants([], sessionID: session.sessionID)
    await #expect(throws: FloorPlanRepositoryError.permissionDenied) {
        try await other.loadForSession(session.sessionID, expectedReference: request.reference)
    }
}

@Test func repositoryRejectsUnauthenticatedOperations() async throws {
    let store = backend(), request = try registration()
    let client = store.client(authenticatedUID: nil)
    await #expect(throws: FloorPlanRepositoryError.unauthenticated) { try await client.register(request) }
    await #expect(throws: FloorPlanRepositoryError.unauthenticated) { try await client.list(pageSize: 20, cursor: nil) }
    await #expect(throws: FloorPlanRepositoryError.unauthenticated) { try await client.loadOwned(request.reference) }
    await #expect(throws: FloorPlanRepositoryError.unauthenticated) {
        try await client.loadForSession(UUID(), expectedReference: request.reference)
    }
    await #expect(throws: FloorPlanRepositoryError.unauthenticated) {
        try await client.createSession(.init(requestID: UUID(), name: "훈련", floorPlan: request.reference))
    }
    #expect(await store.counts.ready == 0)
}

@Test func stagedRegistrationIsHiddenAndResumesWithTheSameRequest() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    await store.failOnce(at: .afterStagingRegistration)
    await #expect(throws: FloorPlanRepositoryError.unavailable) { try await owner.register(request) }
    #expect(await store.counts.pending == 1)
    #expect(try await owner.list(pageSize: 20, cursor: nil).items.isEmpty)
    await #expect(throws: FloorPlanRepositoryError.notReady) { try await owner.loadOwned(request.reference) }
    await #expect(throws: FloorPlanRepositoryError.notReady) {
        try await owner.createSession(.init(requestID: UUID(), name: "훈련", floorPlan: request.reference))
    }
    let changed = RegisterFloorPlanRequest(requestID: request.requestID, name: "다른 이름", reference: request.reference, files: request.files)
    await #expect(throws: FloorPlanRepositoryError.conflict) { try await owner.register(changed) }
    #expect(try await owner.register(request).reference == request.reference)
    let counts = await store.counts
    #expect(counts.ready == 1 && counts.pending == 0 && counts.sessions == 0)
}

@Test func registrationRetryRecoversLostResponseWithoutDuplicateOrOverwrite() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    await store.failOnce(at: .afterRegistrationCommit)
    await #expect(throws: FloorPlanRepositoryError.unavailable) { try await owner.register(request) }
    #expect(await store.counts.ready == 1)
    let result = try await owner.register(request)
    #expect(try await owner.register(request) == result)
    let altered = RegisterFloorPlanRequest(requestID: request.requestID, name: "덮어쓰기", reference: request.reference, files: request.files)
    await #expect(throws: FloorPlanRepositoryError.conflict) { try await owner.register(altered) }
    // Even changed bytes with an unchanged (now invalid) hash cannot bypass retry checks.
    let files = FloorPlanFiles(imagePNG: request.files.imagePNG, navigationMapJSON: request.files.navigationMapJSON + Data([32]),
                              resolvedMask: request.files.resolvedMask)
    let bytesChanged = RegisterFloorPlanRequest(requestID: request.requestID, name: request.name, reference: request.reference, files: files)
    await #expect(throws: FloorPlanRepositoryError.conflict) { try await owner.register(bytesChanged) }
    let newRequest = RegisterFloorPlanRequest(requestID: UUID(), name: request.name, reference: request.reference, files: request.files)
    await #expect(throws: FloorPlanRepositoryError.conflict) { try await owner.register(newRequest) }
    #expect(try await owner.loadOwned(request.reference).files.navigationMapJSON == request.files.navigationMapJSON)
    #expect(await store.counts.ready == 1)
}

@Test func concurrentDuplicateRegistrationsPublishOnlyOnce() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    let results = try await withThrowingTaskGroup(of: FloorPlanSummary.self) { group in
        for _ in 0..<12 { group.addTask { try await owner.register(request) } }
        var results: [FloorPlanSummary] = []
        for try await result in group { results.append(result) }
        return results
    }
    #expect(results.count == 12 && results.allSatisfy { $0.reference == request.reference })
    #expect(await store.counts.ready == 1)
}

@Test func concurrentConflictingRequestsCannotBothPublish() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    let changed = RegisterFloorPlanRequest(requestID: request.requestID, name: "다른 이름", reference: request.reference, files: request.files)
    let successes = try await withThrowingTaskGroup(of: Bool.self) { group in
        for payload in [request, changed] {
            group.addTask {
                do { _ = try await owner.register(payload); return true }
                catch FloorPlanRepositoryError.conflict { return false }
            }
        }
        var count = 0
        for try await success in group { if success { count += 1 } }
        return count
    }
    #expect(successes == 1)
    #expect(await store.counts.ready == 1)
}

@Test func publishedRevisionIdentityCannotBeReusedForAnotherMap() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    _ = try await owner.register(request)
    let floorID = UUID()
    var json = try #require(JSONSerialization.jsonObject(with: request.files.navigationMapJSON) as? [String: Any])
    json["floorPlanID"] = floorID.uuidString.lowercased()
    let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    let ref = FloorPlanReference(floorPlanID: floorID, revisionID: request.reference.revisionID,
                                navigationSHA256: FloorPlanJSON.sha256(bytes))
    let collision = RegisterFloorPlanRequest(requestID: UUID(), name: "새 도면", reference: ref,
        files: FloorPlanFiles(imagePNG: request.files.imagePNG, navigationMapJSON: bytes, resolvedMask: request.files.resolvedMask))
    await #expect(throws: FloorPlanRepositoryError.conflict) { try await owner.register(collision) }
    #expect(await store.counts.ready == 1)
}

@Test func sessionRetryIsIdempotentAndCannotReplaceItsMap() async throws {
    let store = backend()
    let owner = store.client(authenticatedUID: "owner")
    let first = try registration(), second = try registration(newIdentity: true)
    _ = try await owner.register(first)
    _ = try await owner.register(second)
    let request = CreateFloorPlanSessionRequest(requestID: UUID(), name: "훈련", floorPlan: first.reference)
    await store.failOnce(at: .afterSessionCommit)
    await #expect(throws: FloorPlanRepositoryError.unavailable) { try await owner.createSession(request) }
    let session = try await owner.createSession(request)
    #expect(try await owner.createSession(request) == session)
    let replacement = CreateFloorPlanSessionRequest(requestID: request.requestID, name: request.name, floorPlan: second.reference)
    await #expect(throws: FloorPlanRepositoryError.conflict) { try await owner.createSession(replacement) }
    await #expect(throws: FloorPlanValidationError.referenceMismatch) {
        try await owner.loadForSession(session.sessionID, expectedReference: second.reference)
    }
    #expect(try await owner.loadForSession(session.sessionID, expectedReference: first.reference).reference == first.reference)
    #expect(await store.counts.sessions == 1)
}

@Test func concurrentSessionCreationRetriesProduceOneBinding() async throws {
    let store = backend(), map = try registration()
    let owner = store.client(authenticatedUID: "owner")
    _ = try await owner.register(map)
    let request = CreateFloorPlanSessionRequest(requestID: UUID(), name: "훈련", floorPlan: map.reference)
    let ids = try await withThrowingTaskGroup(of: UUID.self) { group in
        for _ in 0..<12 { group.addTask { try await owner.createSession(request).sessionID } }
        var ids: Set<UUID> = []
        for try await id in group { ids.insert(id) }
        return ids
    }
    #expect(ids.count == 1)
    #expect(await store.counts.sessions == 1)
}

@Test func requestIDsAreScopedToIdentityAndOperation() async throws {
    let store = backend(), id = UUID()
    let a = store.client(authenticatedUID: "a"), b = store.client(authenticatedUID: "b")
    let first = try registration(requestID: id), second = try registration(requestID: id, newIdentity: true)
    _ = try await a.register(first)
    // A different UID cannot replay A's request to obtain A's published result.
    await #expect(throws: FloorPlanRepositoryError.conflict) { try await b.register(first) }
    _ = try await b.register(second)
    let s1 = try await a.createSession(.init(requestID: id, name: "A", floorPlan: first.reference))
    let s2 = try await b.createSession(.init(requestID: id, name: "B", floorPlan: second.reference))
    #expect(s1.sessionID != s2.sessionID)
    #expect(try await a.list(pageSize: 20, cursor: nil).items.map(\.reference) == [first.reference])
    #expect(try await b.list(pageSize: 20, cursor: nil).items.map(\.reference) == [second.reference])
}

@Test func invalidFilesNeverReserveOrPublishARegistration() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    let bad = RegisterFloorPlanRequest(requestID: request.requestID, name: request.name, reference: request.reference,
        files: FloorPlanFiles(imagePNG: Data([0]), navigationMapJSON: request.files.navigationMapJSON, resolvedMask: request.files.resolvedMask))
    await #expect(throws: FloorPlanValidationError.integrityMismatch) { try await owner.register(bad) }
    let counts = await store.counts
    #expect(counts.ready == 0 && counts.pending == 0)
    _ = try await owner.register(request)
}

@Test func transientPreCommitAndReadFailuresAreNotEmptySuccesses() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    await store.failOnce(at: .beforeRegistration)
    await #expect(throws: FloorPlanRepositoryError.unavailable) { try await owner.register(request) }
    #expect(await store.counts.pending == 0)
    _ = try await owner.register(request)
    let create = CreateFloorPlanSessionRequest(requestID: UUID(), name: "훈련", floorPlan: request.reference)
    await store.failOnce(at: .beforeSessionCreation)
    await #expect(throws: FloorPlanRepositoryError.unavailable) { try await owner.createSession(create) }
    #expect(await store.counts.sessions == 0)
    let session = try await owner.createSession(create)
    await store.failOnce(at: .beforeRead)
    await #expect(throws: FloorPlanRepositoryError.unavailable) { try await owner.list(pageSize: 20, cursor: nil) }
    #expect(try await owner.list(pageSize: 20, cursor: nil).items.count == 1)
    await store.failOnce(at: .beforeRead)
    await #expect(throws: FloorPlanRepositoryError.unavailable) { try await owner.loadOwned(request.reference) }
    await store.failOnce(at: .beforeRead)
    await #expect(throws: FloorPlanRepositoryError.unavailable) {
        try await owner.loadForSession(session.sessionID, expectedReference: request.reference)
    }
}

@Test func paginationIsOwnerScopedRepeatableAndSnapshotBased() async throws {
    let store = backend(), first = try registration(), second = try registration(newIdentity: true)
    let owner = store.client(authenticatedUID: "owner")
    _ = try await owner.register(first)
    _ = try await owner.register(second)
    let page1 = try await owner.list(pageSize: 1, cursor: nil)
    let cursor = try #require(page1.nextCursor)
    _ = try await owner.register(registration(newIdentity: true))
    let page2 = try await owner.list(pageSize: 1, cursor: cursor)
    #expect(page2.nextCursor == nil)
    #expect(Set((page1.items + page2.items).map(\.reference)) == [first.reference, second.reference])
    #expect(try await owner.list(pageSize: 1, cursor: cursor).items == page2.items)
    await #expect(throws: FloorPlanRepositoryError.invalidCursor) {
        try await store.client(authenticatedUID: "other").list(pageSize: 1, cursor: cursor)
    }
    await #expect(throws: FloorPlanRepositoryError.invalidCursor) { try await owner.list(pageSize: 1, cursor: "unknown") }
    for count in [0, -1, 101, Int.max] {
        await #expect(throws: FloorPlanRepositoryError.invalidRequest) { try await owner.list(pageSize: count, cursor: nil) }
    }
}

@Test func invalidRequestsAndMissingOrMismatchedMapsAreExplicit() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    await #expect(throws: FloorPlanRepositoryError.invalidRequest) { try await owner.register(registration(name: " \n")) }
    await #expect(throws: FloorPlanRepositoryError.notFound) { try await owner.loadOwned(request.reference) }
    await #expect(throws: FloorPlanRepositoryError.notFound) {
        try await owner.createSession(.init(requestID: UUID(), name: "훈련", floorPlan: request.reference))
    }
    _ = try await owner.register(request)
    let wrong = FloorPlanReference(floorPlanID: request.reference.floorPlanID, revisionID: UUID(), navigationSHA256: request.reference.navigationSHA256)
    await #expect(throws: FloorPlanValidationError.referenceMismatch) { try await owner.loadOwned(wrong) }
    await #expect(throws: FloorPlanValidationError.referenceMismatch) {
        try await owner.createSession(.init(requestID: UUID(), name: "훈련", floorPlan: wrong))
    }
    await #expect(throws: FloorPlanRepositoryError.invalidRequest) {
        try await owner.createSession(.init(requestID: UUID(), name: "", floorPlan: request.reference))
    }
}

@Test func cancelledRepositoryOperationStaysCancellationAndDoesNotPublish() async throws {
    let store = backend(), request = try registration()
    let owner = store.client(authenticatedUID: "owner")
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await owner.register(request)
    }
    do { _ = try await task.value; Issue.record("Cancellation expected") }
    catch is CancellationError { }
    catch { Issue.record("Unexpected error: \(error)") }
    let counts = await store.counts
    #expect(counts.ready == 0 && counts.pending == 0)
    _ = try await owner.register(request)
}

@Test func droppingClientsAndBackendDoesNotLeaveARetainCycle() async throws {
    weak var released: InMemoryFloorPlanStore?
    func exercise() async throws {
        let store = backend()
        released = store
        let client = store.client(authenticatedUID: "owner")
        _ = try await client.register(registration())
        _ = try await client.list(pageSize: 1, cursor: nil)
    }
    try await exercise()
    #expect(released == nil)
}
