import Foundation
import CQBCore

/// Single-process test backend; not server authentication, persistence or upload.
/// Harness seeds authoritative sessions/member bindings and verified raw files.
/// No await inside mutations: ready publication and first selection are atomic.
public actor InMemoryTrackResultStore {
    public enum FailurePoint: Hashable, Sendable { case beforePublish, afterStaging, afterCommit, afterSelection, beforeRead }
    private struct Session {
        let ownerUID: String
        let map: ValidatedFloorPlan
        var members: [UUID: String]
    }
    private struct RequestKey: Hashable { let uid: String; let requestID: UUID }
    private struct Entry {
        let request: PublishTrackResultRequest
        let result: ValidatedTrackResult
        var ready: Bool
    }
    private var sessions: [UUID: Session] = [:]
    private var rawFiles: [TrackIdentity: ValidatedRawTrack] = [:]
    private var entries: [UUID: Entry] = [:]
    private var publications: [RequestKey: UUID] = [:]
    private var selectionRequests: [RequestKey: SelectTrackResultRequest] = [:]
    private var selected: [TrackIdentity: UUID] = [:]
    private var failures: [FailurePoint: Int] = [:]

    public init() {}
    public nonisolated func client(authenticatedUID: String?) -> InMemoryTrackResultClient {
        InMemoryTrackResultClient(store: self, uid: authenticatedUID)
    }
    /// Harness only. Session identity and map cannot be overwritten.
    public func seedSession(id: UUID, ownerUID: String, members: [UUID: String], map: ValidatedFloorPlan) throws {
        guard sessions[id] == nil, !ownerUID.isEmpty, members.values.allSatisfy({ !$0.isEmpty }) else {
            throw TrackRepositoryError.conflict
        }
        sessions[id] = Session(ownerUID: ownerUID, map: map, members: members)
    }
    /// Harness-only revocation/participation, not a public join API.
    public func setMembers(_ members: [UUID: String], sessionID: UUID) throws {
        guard sessions[sessionID] != nil else { throw TrackRepositoryError.notFound }
        guard members.values.allSatisfy({ !$0.isEmpty }) else { throw TrackRepositoryError.conflict }
        sessions[sessionID]?.members = members
    }
    /// Simulates a trusted raw-upload completion. It is intentionally absent from
    /// the app-facing repository: callers cannot claim confirmation with a Bool.
    public func confirmRaw(_ raw: ValidatedRawTrack) throws {
        let identity = raw.document.identity
        guard let session = sessions[identity.sessionID] else { throw TrackRepositoryError.notFound }
        guard session.members[identity.memberID] != nil else { throw TrackRepositoryError.permissionDenied }
        guard raw.document.floorPlan == session.map.reference else { throw TrackValidationError.referenceMismatch }
        if let existing = rawFiles[identity], existing.bytes != raw.bytes { throw TrackRepositoryError.conflict }
        rawFiles[identity] = raw
    }
    public func failOnce(at point: FailurePoint) { failures[point, default: 0] += 1 }
    public var counts: (ready: Int, pending: Int) {
        let ready = entries.values.filter(\.ready).count
        return (ready, entries.count - ready)
    }

    fileprivate func publish(_ request: PublishTrackResultRequest, uid: String?) throws -> ValidatedTrackResult {
        let uid = try authenticate(uid)
        let session = try authorize(request.identity, uid: uid, write: true)
        guard let raw = rawFiles[request.identity] else { throw TrackRepositoryError.notReady }
        let key = RequestKey(uid: uid, requestID: request.requestID)
        let resultID: UUID
        if let id = publications[key], let entry = entries[id] {
            guard entry.request.identity == request.identity, entry.request.resultJSON == request.resultJSON else {
                throw TrackRepositoryError.conflict
            }
            if entry.ready { return entry.result }
            resultID = id
        } else {
            try fail(.beforePublish)
            let validated = try TrackDocumentValidator.result(request.resultJSON, raw: raw, floorPlan: session.map)
            guard validated.document.status != .failed else { throw TrackRepositoryError.notUsable }
            resultID = validated.document.resultID
            guard entries[resultID] == nil else { throw TrackRepositoryError.conflict }
            try Task.checkCancellation()
            entries[resultID] = Entry(request: request, result: validated, ready: false)
            publications[key] = resultID
        }
        try fail(.afterStaging)
        try Task.checkCancellation()
        entries[resultID]?.ready = true
        if selected[request.identity] == nil { selected[request.identity] = resultID }
        try fail(.afterCommit)
        return entries[resultID]!.result
    }

    fileprivate func select(_ request: SelectTrackResultRequest, uid: String?) throws {
        let uid = try authenticate(uid)
        _ = try authorize(request.identity, uid: uid, write: true)
        let key = RequestKey(uid: uid, requestID: request.requestID)
        if let previous = selectionRequests[key] {
            guard previous == request else { throw TrackRepositoryError.conflict }
            return // A later selection must not be rolled back by an old retry.
        }
        guard let entry = entries[request.resultID], entry.result.document.identity == request.identity else {
            throw TrackRepositoryError.notFound
        }
        guard entry.ready else { throw TrackRepositoryError.notReady }
        guard selected[request.identity] == request.expectedSelectedResultID else { throw TrackRepositoryError.conflict }
        try Task.checkCancellation()
        selected[request.identity] = request.resultID
        selectionRequests[key] = request
        try fail(.afterSelection)
    }

    fileprivate func loadSelected(_ identity: TrackIdentity, uid: String?) throws -> ValidatedTrackResult? {
        let uid = try authenticate(uid)
        _ = try authorize(identity, uid: uid, write: false)
        try fail(.beforeRead)
        guard let id = selected[identity] else { return nil }
        return try ready(id, identity: identity)
    }
    fileprivate func load(_ id: UUID, identity: TrackIdentity, uid: String?) throws -> ValidatedTrackResult {
        let uid = try authenticate(uid)
        _ = try authorize(identity, uid: uid, write: false)
        try fail(.beforeRead)
        return try ready(id, identity: identity)
    }
    private func ready(_ id: UUID, identity: TrackIdentity) throws -> ValidatedTrackResult {
        guard let entry = entries[id], entry.result.document.identity == identity else { throw TrackRepositoryError.notFound }
        guard entry.ready else { throw TrackRepositoryError.notReady }
        return entry.result
    }
    private func authenticate(_ uid: String?) throws -> String {
        try Task.checkCancellation()
        guard let uid, !uid.isEmpty else { throw TrackRepositoryError.unauthenticated }
        return uid
    }
    private func authorize(_ identity: TrackIdentity, uid: String, write: Bool) throws -> Session {
        guard let session = sessions[identity.sessionID] else { throw TrackRepositoryError.notFound }
        let own = session.members[identity.memberID] == uid
        guard own || (!write && session.ownerUID == uid) else { throw TrackRepositoryError.permissionDenied }
        return session
    }
    private func fail(_ point: FailurePoint) throws {
        if failures[point, default: 0] > 0 {
            failures[point, default: 0] -= 1
            throw TrackRepositoryError.unavailable
        }
    }
}

public struct InMemoryTrackResultClient: TrackResultRepository {
    private let store: InMemoryTrackResultStore
    private let uid: String?
    fileprivate init(store: InMemoryTrackResultStore, uid: String?) { self.store = store; self.uid = uid }
    public func publishUsable(_ request: PublishTrackResultRequest) async throws -> ValidatedTrackResult {
        try await store.publish(request, uid: uid)
    }
    public func select(_ request: SelectTrackResultRequest) async throws { try await store.select(request, uid: uid) }
    public func loadSelected(for identity: TrackIdentity) async throws -> ValidatedTrackResult? {
        try await store.loadSelected(identity, uid: uid)
    }
    public func load(resultID: UUID, for identity: TrackIdentity) async throws -> ValidatedTrackResult {
        try await store.load(resultID, identity: identity, uid: uid)
    }
}
