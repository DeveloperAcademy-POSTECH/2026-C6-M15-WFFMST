import CryptoKit
import Foundation

public enum FloorPlanJSON {
    public static let maximumManifestBytes = 1_024 * 1_024

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes transfer values only. Use FloorPlanValidator before consuming them.
    public static func decodeManifest(_ data: Data) throws -> FloorPlanManifest {
        guard !data.isEmpty, data.count <= maximumManifestBytes,
              String(data: data, encoding: .utf8) != nil else {
            throw FloorPlanValidationError.invalidManifest
        }
        let decoder = JSONDecoder()
        struct Version: Decodable { let schemaVersion: Int }
        let version: Int
        do { version = try decoder.decode(Version.self, from: data).schemaVersion }
        catch { throw FloorPlanValidationError.invalidManifest }
        guard version == 1 else { throw FloorPlanValidationError.unsupportedSchema(version) }
        do { return try decoder.decode(FloorPlanManifest.self, from: data) }
        catch { throw FloorPlanValidationError.invalidManifest }
    }

    /// Writer is not a validator. Finalize once, hash these bytes, reuse on retry.
    public static func encodeManifest(_ manifest: FloorPlanManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do { data = try encoder.encode(manifest) }
        catch { throw FloorPlanValidationError.invalidManifest }
        guard data.count <= maximumManifestBytes else { throw FloorPlanValidationError.invalidManifest }
        return data
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
