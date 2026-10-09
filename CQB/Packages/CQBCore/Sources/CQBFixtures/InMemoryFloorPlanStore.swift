import Foundation
import CQBCore

/// Test/development backend shared by explicitly scoped clients in one process.
/// This is not authentication, a PIN join service, disk persistence or networking.
/// Actor serialization makes publication/idempotency atomic. Validation runs on
/// this actor, not MainActor; there are no suspension points inside mutations.
public actor InMemoryFloorPlanStore {
    /// Fixture-only resource limit, not a production cursor lifetime policy.
    public static let maximumPageSnapshots = 16

    public enum FailurePoint: Hashable, Sendable {
        case beforeRegistration
        case afterStagingRegistration
        case afterRegistrationCommit
        case beforeSessionCreation
        case afterSessionCommit
        case beforeRead
    }

    private struct RequestKey: Hashable {
        let uid: String
        let id: UUID
    }

    private struct Registration {
        let key: RequestKey
        let request: RegisterFloorPlanRequest
        let map: ValidatedFloorPlan
        var ready: Bool
        var summary: FloorPlanSummary { FloorPlanSummary(name: request.name, reference: map.reference) }
    }

    private struct SessionEntry {
        let ownerUID: String
        let binding: SessionFloorPlanBinding
        var participantUIDs: Set<String>
    }

    private struct SessionRequest {
        let request: CreateFloorPlanSessionRequest
        let binding: SessionFloorPlanBinding
    }

    private struct PageSnapshot {
        let uid: String
        let items: [FloorPlanSummary]
    }

    private let validator: FloorPlanValidator
    private var registrations: [UUID: Registration] = [:]
    private var registrationRequests: [RequestKey: UUID] = [:]
    private var revisionOwners: [UUID: UUID] = [:]
    private var sessions: [UUID: SessionEntry] = [:]
    private var sessionRequests: [RequestKey: SessionRequest] = [:]
    private var pages: [UUID: PageSnapshot] = [:]
    // FIFO order contains only live snapshots and is bounded with `pages`.
    private var pageSnapshotOrder: [UUID] = []
    private var failures: [FailurePoint: Int] = [:]

    public init(imageValidator: any FloorPlanImageValidating) {
        validator = FloorPlanValidator(imageValidator: imageValidator)
    }

    /// Composition/test harness only. Production authentication must come from
    /// the server/SDK; a view must not manufacture an authenticated UID.
    public nonisolated func client(authenticatedUID: String?) -> InMemoryFloorPlanClient {
        InMemoryFloorPlanClient(store: self, uid: authenticatedUID)
    }

    public func failOnce(at point: FailurePoint) {
        failures[point, default: 0] += 1
    }

    /// Models already-verified session participation, not a public join endpoint.
    /// Replacing the set also allows tests to check revoked access on a cached map.
    public func setParticipants(_ uids: Set<String>, sessionID: UUID) throws {
        guard sessions[sessionID] != nil else { throw FloorPlanRepositoryError.notFound }
        sessions[sessionID]?.participantUIDs = uids
    }

    public var counts: (ready: Int, pending: Int, sessions: Int) {
        let ready = registrations.values.filter(\.ready).count
        return (ready, registrations.count - ready, sessions.count)
    }

    /// Test diagnostics: retained summary entries, not allocated bytes or map files.
    public var pageCacheCounts: (snapshots: Int, summaries: Int) {
        (pages.count, pages.values.reduce(0) { $0 + $1.items.count })
    }

    func register(_ request: RegisterFloorPlanRequest, uid: String?) throws -> FloorPlanSummary {
        let uid = try authenticated(uid)
        try validateName(request.name)
        let key = RequestKey(uid: uid, id: request.requestID)
        if let floorID = registrationRequests[key], let previous = registrations[floorID] {
            guard samePayload(previous.request, request) else { throw FloorPlanRepositoryError.conflict }
            if previous.ready { return previous.summary }
        } else {
            // MVP registration only: edits/new revisions need a separate contract.
            guard registrations[request.reference.floorPlanID] == nil,
                  revisionOwners[request.reference.revisionID] == nil else {
                throw FloorPlanRepositoryError.conflict
            }
        }
        try failIfNeeded(.beforeRegistration)
        if registrationRequests[key] == nil {
            let map = try validator.validate(files: request.files, reference: request.reference)
            try Task.checkCancellation()
            registrations[request.reference.floorPlanID] = Registration(key: key, request: request, map: map, ready: false)
            registrationRequests[key] = request.reference.floorPlanID
            revisionOwners[request.reference.revisionID] = request.reference.floorPlanID
        }
        // Failure leaves a reserved, nonpublic upload. Same request can resume it.
        try failIfNeeded(.afterStagingRegistration)
        try Task.checkCancellation()
        registrations[request.reference.floorPlanID]?.ready = true
        // Commit happened; losing the response must not undo it or allocate again.
        try failIfNeeded(.afterRegistrationCommit)
        try Task.checkCancellation()
        return FloorPlanSummary(name: request.name, reference: request.reference)
    }

    func list(pageSize: Int, cursor: String?, uid: String?) throws -> FloorPlanPage {
        let uid = try authenticated(uid)
        guard (1...100).contains(pageSize) else { throw FloorPlanRepositoryError.invalidRequest }
        let snapshotID: UUID
        let snapshot: PageSnapshot
        let offset: Int
        if let cursor {
            // Fixture codec only; callers still treat this as opaque. No registry
            // or copied tail is allocated for each position/retry in a snapshot.
            let fields = cursor.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 2, let id = UUID(uuidString: String(fields[0])),
                  let start = Int(fields[1]), String(start) == fields[1],
                  let existing = pages[id], existing.uid == uid,
                  start > 0, start < existing.items.count else {
                throw FloorPlanRepositoryError.invalidCursor
            }
            snapshotID = id
            snapshot = existing
            offset = start
        } else {
            let items = registrations.values.filter { $0.ready && $0.key.uid == uid }
                .map(\.summary).sorted { $0.reference.floorPlanID.uuidString < $1.reference.floorPlanID.uuidString }
            snapshotID = UUID()
            snapshot = PageSnapshot(uid: uid, items: items)
            offset = 0
        }
        try failIfNeeded(.beforeRead)
        let end = offset + min(pageSize, snapshot.items.count - offset)
        let items = Array(snapshot.items[offset..<end])
        let next = end < snapshot.items.count ? "\(snapshotID.uuidString):\(end)" : nil
        try Task.checkCancellation()
        if cursor == nil, next != nil {
            // Only a successful, multipage first read changes the cache. Retries
            // (including terminal pages) neither allocate nor renew its lifetime.
            if pageSnapshotOrder.count == Self.maximumPageSnapshots {
                pages.removeValue(forKey: pageSnapshotOrder.removeFirst())
            }
            pages[snapshotID] = snapshot
            pageSnapshotOrder.append(snapshotID)
        }
        return FloorPlanPage(items: items, nextCursor: next)
    }

    func loadOwned(_ reference: FloorPlanReference, uid: String?) throws -> ValidatedFloorPlan {
        let uid = try authenticated(uid)
        let record = try ownedReady(reference, uid: uid)
        try failIfNeeded(.beforeRead)
        return record.map
    }

    func loadForSession(_ id: UUID, expectedReference: FloorPlanReference,
                                    uid: String?) throws -> ValidatedFloorPlan {
        let uid = try authenticated(uid)
        // Hide even the binding from nonparticipants. Possessing a reference is
        // never sufficient to read a session or its library files.
        guard let session = sessions[id], session.ownerUID == uid || session.participantUIDs.contains(uid) else {
            throw FloorPlanRepositoryError.permissionDenied
        }
        guard session.binding.floorPlan == expectedReference else { throw FloorPlanValidationError.referenceMismatch }
        let record = try ownedReady(session.binding.floorPlan, uid: session.ownerUID)
        try failIfNeeded(.beforeRead)
        return record.map
    }

    func createSession(_ request: CreateFloorPlanSessionRequest, uid: String?) throws -> SessionFloorPlanBinding {
        let uid = try authenticated(uid)
        try validateName(request.name)
        let key = RequestKey(uid: uid, id: request.requestID)
        if let previous = sessionRequests[key] {
            guard previous.request == request else { throw FloorPlanRepositoryError.conflict }
            return previous.binding
        }
        _ = try ownedReady(request.floorPlan, uid: uid)
        try failIfNeeded(.beforeSessionCreation)
        try Task.checkCancellation()
        let binding = SessionFloorPlanBinding(sessionID: UUID(), name: request.name, floorPlan: request.floorPlan)
        sessions[binding.sessionID] = SessionEntry(ownerUID: uid, binding: binding, participantUIDs: [])
        sessionRequests[key] = SessionRequest(request: request, binding: binding)
        try failIfNeeded(.afterSessionCommit)
        try Task.checkCancellation()
        return binding
    }

    private func ownedReady(_ reference: FloorPlanReference, uid: String) throws -> Registration {
        guard let record = registrations[reference.floorPlanID] else { throw FloorPlanRepositoryError.notFound }
        guard record.key.uid == uid else { throw FloorPlanRepositoryError.permissionDenied }
        guard record.map.reference == reference else { throw FloorPlanValidationError.referenceMismatch }
        guard record.ready else { throw FloorPlanRepositoryError.notReady }
        return record
    }

    private func authenticated(_ uid: String?) throws -> String {
        try Task.checkCancellation()
        guard let uid, !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FloorPlanRepositoryError.unauthenticated
        }
        return uid
    }

    private func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FloorPlanRepositoryError.invalidRequest
        }
    }

    private func failIfNeeded(_ point: FailurePoint) throws {
        guard let count = failures[point], count > 0 else { return }
        failures[point] = count - 1
        throw FloorPlanRepositoryError.unavailable
    }

    private func samePayload(_ lhs: RegisterFloorPlanRequest, _ rhs: RegisterFloorPlanRequest) -> Bool {
        lhs.name == rhs.name && lhs.reference == rhs.reference
            && lhs.files.imagePNG == rhs.files.imagePNG
            && lhs.files.navigationMapJSON == rhs.files.navigationMapJSON
            && lhs.files.resolvedMask == rhs.files.resolvedMask
    }
}
