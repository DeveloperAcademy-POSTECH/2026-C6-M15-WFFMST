import Foundation

/// Fixed file-level sample for contract review. This is not a repository or a
/// validated CQBCore model. It never generates IDs or normalizes/re-encodes data.
public enum NormalFloorPlanFixture {
    public enum File: String, CaseIterable, Sendable {
        case image = "original.png"
        case mask = "resolved-mask.bin"
        case manifest = "navigation-map.json"
        case reference = "reference.json"
        case expectations = "expected.json"
    }

    public static func data(for file: File) throws -> Data {
        guard let root = Bundle.module.url(forResource: "FloorPlans", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: root.appendingPathComponent("normal-v1", isDirectory: true)
            .appendingPathComponent(file.rawValue))
    }
}
