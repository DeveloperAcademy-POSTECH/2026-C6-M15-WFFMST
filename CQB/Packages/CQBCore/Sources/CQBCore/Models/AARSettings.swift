import Foundation

/// A presentation choice, not playback execution or a recording's result selection.
public enum AARDisplayMode: String, Codable, Equatable, Sendable {
    case movement
    case video
}

/// Display intent for one session. The member IDs identify session participants,
/// not authentication users or recordings. The set does not define display order.
/// Construction and decoding do not validate relationships or establish access.
/// Initial selection, loading and state transitions remain owned by the app.
public struct AARSettings: Codable, Equatable, Sendable {
    public let sessionID: UUID
    /// Shared by both modes; an empty set means an explicit selection of nobody.
    public let selectedMemberIDs: Set<UUID>
    public let displayMode: AARDisplayMode

    public init(sessionID: UUID, selectedMemberIDs: Set<UUID>, displayMode: AARDisplayMode) {
        self.sessionID = sessionID
        self.selectedMemberIDs = selectedMemberIDs
        self.displayMode = displayMode
    }
}
