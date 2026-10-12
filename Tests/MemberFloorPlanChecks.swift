import CQBCore
import CryptoKit
import Foundation

@main
struct MemberFloorPlanChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let files = FloorPlanFiles(
            imagePNG: try Data(contentsOf: root.appendingPathComponent("training-map.pngdata")),
            navigationMapJSON: try Data(contentsOf: root.appendingPathComponent("training-navigation.json")),
            resolvedMask: try Data(contentsOf: root.appendingPathComponent("training-mask.bin"))
        )
        let originalManifest = try JSONDecoder().decode(FloorPlanManifest.self, from: files.navigationMapJSON)
        let firstReference = FloorPlanReference(
            floorPlanID: originalManifest.floorPlanID,
            navigationSHA256: sha256(files.navigationMapJSON)
        )
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }

        let firstMap = try BundledTrainingMapLoader.load(files: files, for: firstReference, cacheDirectory: cache)
        expect(firstMap.reference == firstReference, "session reference retained")
        expect(FileManager.default.fileExists(atPath: firstMap.imageURL.path), "session image cached")
        expect(firstMap.navigation.grid.isFree(MapPoint(x: 300, y: 300)), "downloaded navigation grid used")

        let secondID = UUID()
        let secondManifest = FloorPlanManifest(
            schemaVersion: originalManifest.schemaVersion,
            floorPlanID: secondID,
            coordinateSystem: originalManifest.coordinateSystem,
            imageWidth: originalManifest.imageWidth,
            imageHeight: originalManifest.imageHeight,
            imageSHA256: originalManifest.imageSHA256,
            scale: originalManifest.scale,
            indoorOutline: originalManifest.indoorOutline,
            navigationGrid: originalManifest.navigationGrid,
            extractionAlgorithmVersion: originalManifest.extractionAlgorithmVersion,
            rasterizationVersion: originalManifest.rasterizationVersion,
            manuallyReviewed: originalManifest.manuallyReviewed
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let secondNavigation = try encoder.encode(secondManifest)
        let secondReference = FloorPlanReference(floorPlanID: secondID, navigationSHA256: sha256(secondNavigation))
        let secondMap = try BundledTrainingMapLoader.load(
            files: FloorPlanFiles(imagePNG: files.imagePNG, navigationMapJSON: secondNavigation,
                resolvedMask: files.resolvedMask),
            for: secondReference,
            cacheDirectory: cache
        )
        expect(firstMap.reference != secondMap.reference, "different session maps remain distinct")
        expect(firstMap.imageURL != secondMap.imageURL, "different maps use different cache paths")

        expectThrows("rejects a mismatched floor-plan reference") {
            _ = try BundledTrainingMapLoader.load(
                files: files,
                for: FloorPlanReference(floorPlanID: secondID, navigationSHA256: firstReference.navigationSHA256),
                cacheDirectory: cache
            )
        }
        expectThrows("rejects an image that does not match the manifest hash") {
            var corrupted = files.imagePNG
            corrupted[corrupted.startIndex + 32] ^= 0xff
            _ = try BundledTrainingMapLoader.load(
                files: FloorPlanFiles(imagePNG: corrupted, navigationMapJSON: files.navigationMapJSON,
                    resolvedMask: files.resolvedMask),
                for: firstReference,
                cacheDirectory: cache
            )
        }
        expectThrows("rejects a navigation file that does not match the session reference") {
            _ = try BundledTrainingMapLoader.load(
                files: files,
                for: FloorPlanReference(floorPlanID: firstReference.floorPlanID, navigationSHA256: String(repeating: "0", count: 64)),
                cacheDirectory: cache
            )
        }
        print("PASS: session floor-plan loading, distinct references, cache isolation, and integrity checks")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }

    private static func expectThrows(_ message: String, _ operation: () throws -> Void) {
        do {
            try operation()
            fatalError("FAIL: \(message)")
        } catch {}
    }
}
