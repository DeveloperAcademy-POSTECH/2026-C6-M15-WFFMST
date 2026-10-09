import Foundation

/// Implementations bind authentication externally. No owner UID or storage path
/// is accepted as proof of access. Shared between Firebase and fixture adapters.
public protocol FloorPlanRepository: Sendable {
    /// Publish only after full validation. Same UID + request ID + exact payload
    /// returns the same result; a changed payload or occupied identity conflicts.
    func register(_ request: RegisterFloorPlanRequest) async throws -> FloorPlanSummary

    /// Ready entries of the authenticated owner only. Page size must be 1...100.
    func list(pageSize: Int, cursor: String?) async throws -> FloorPlanPage

    func loadOwned(_ reference: FloorPlanReference) async throws -> ValidatedFloorPlan

    /// Resolve the authoritative session binding and membership before returning
    /// files. The client's expected reference is a consistency check, not authority.
    func loadForSession(_ sessionID: UUID, expectedReference: FloorPlanReference) async throws -> ValidatedFloorPlan
}

/// Narrow session-creation contract for #14. A production SessionRepository must
/// create its session and this binding atomically, not call an attach/replace API
/// after creating a session. No method to change an existing binding is provided.
public protocol FloorPlanSessionCreating: Sendable {
    func createSession(_ request: CreateFloorPlanSessionRequest) async throws -> SessionFloorPlanBinding
}
