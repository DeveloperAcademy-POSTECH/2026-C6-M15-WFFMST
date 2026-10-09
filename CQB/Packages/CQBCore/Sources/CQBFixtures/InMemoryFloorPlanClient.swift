import Foundation
import CQBCore

/// Immutable identity scope; multiple clients can share one in-process store.
/// Only the store factory can create it. Do not treat this as real authentication.
public struct InMemoryFloorPlanClient: FloorPlanRepository, FloorPlanSessionCreating {
    private let store: InMemoryFloorPlanStore
    private let uid: String?

    init(store: InMemoryFloorPlanStore, uid: String?) {
        self.store = store
        self.uid = uid
    }

    public func register(_ request: RegisterFloorPlanRequest) async throws -> FloorPlanSummary {
        try await store.register(request, uid: uid)
    }

    public func list(pageSize: Int, cursor: String?) async throws -> FloorPlanPage {
        try await store.list(pageSize: pageSize, cursor: cursor, uid: uid)
    }

    public func loadOwned(_ reference: FloorPlanReference) async throws -> ValidatedFloorPlan {
        try await store.loadOwned(reference, uid: uid)
    }

    public func loadForSession(_ sessionID: UUID, expectedReference: FloorPlanReference) async throws -> ValidatedFloorPlan {
        try await store.loadForSession(sessionID, expectedReference: expectedReference, uid: uid)
    }

    public func createSession(_ request: CreateFloorPlanSessionRequest) async throws -> SessionFloorPlanBinding {
        try await store.createSession(request, uid: uid)
    }
}
