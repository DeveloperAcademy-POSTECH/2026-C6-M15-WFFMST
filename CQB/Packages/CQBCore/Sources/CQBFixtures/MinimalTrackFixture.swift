import Foundation

/// Hand-authored contract review samples, not V13 output or a production track schema.
/// This loader preserves file bytes; it does not validate or publish a route.
public enum MinimalTrackFixture {
    public enum File: String, CaseIterable, Sendable {
        case normalRaw = "normal-raw.json"
        case trackingGapRaw = "tracking-gap-raw.json"
        case searchLimitRaw = "search-limit-raw.json"
        case insufficientMovementRaw = "insufficient-movement-raw.json"
        case solverSnapshots = "solver-snapshots.json"
        case expectations = "expected.json"
    }

    public static func data(for file: File) throws -> Data {
        guard let root = Bundle.module.url(forResource: "Tracks", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: root.appendingPathComponent("minimal-v1", isDirectory: true)
            .appendingPathComponent(file.rawValue))
    }
}
