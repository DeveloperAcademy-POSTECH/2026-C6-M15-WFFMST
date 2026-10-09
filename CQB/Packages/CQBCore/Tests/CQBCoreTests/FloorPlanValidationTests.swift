import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import CQBCore
import CQBFixtures
import CQBImageIO

// No @testable import: exercise the exact boundary available to app consumers.
private struct Input {
    let files: FloorPlanFiles
    let reference: FloorPlanReference
}

private func fixture() throws -> Input {
    Input(files: FloorPlanFiles(imagePNG: try NormalFloorPlanFixture.data(for: .image),
        navigationMapJSON: try NormalFloorPlanFixture.data(for: .manifest),
        resolvedMask: try NormalFloorPlanFixture.data(for: .mask)),
        reference: try JSONDecoder().decode(FloorPlanReference.self,
            from: NormalFloorPlanFixture.data(for: .reference)))
}

/// Rehash modified input so semantic tests reach the production validator rather
/// than all failing early on the checksum. Original reference IDs stay fixed.
private func changed(image: Data? = nil, mask: Data? = nil,
                     _ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Input {
    let input = try fixture()
    var json = try #require(JSONSerialization.jsonObject(with: input.files.navigationMapJSON) as? [String: Any])
    if let image { json["imageSHA256"] = FloorPlanJSON.sha256(image) }
    if let mask {
        var grid = try #require(json["navigationGrid"] as? [String: Any])
        grid["maskSHA256"] = FloorPlanJSON.sha256(mask)
        json["navigationGrid"] = grid
    }
    mutate(&json)
    let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    return Input(files: FloorPlanFiles(imagePNG: image ?? input.files.imagePNG,
        navigationMapJSON: bytes, resolvedMask: mask ?? input.files.resolvedMask),
        reference: FloorPlanReference(floorPlanID: input.reference.floorPlanID,
            revisionID: input.reference.revisionID, navigationSHA256: FloorPlanJSON.sha256(bytes)))
}

private func validate(_ input: Input) throws -> ValidatedFloorPlan {
    try FloorPlanValidator(imageValidator: PNGFloorPlanImageValidator())
        .validate(files: input.files, reference: input.reference)
}

@Test func productionReaderMatchesAllFixtureExpectations() throws {
    let input = try fixture()
    let map = try validate(input)
    let expected = try #require(JSONSerialization.jsonObject(with: NormalFloorPlanFixture.data(for: .expectations)) as? [String: Any])
    #expect(map.reference == input.reference)
    #expect(map.files.navigationMapJSON == input.files.navigationMapJSON)
    #expect(map.imagePNG == input.files.imagePNG && map.resolvedMask == input.files.resolvedMask)
    #expect(map.pixelsPerMeter == expected["pixelsPerMeter"] as? Double)
    #expect(map.metersPerCell == expected["metersPerCell"] as? Double)
    let samples = try #require(expected["samples"] as? [[String: Any]])
    for sample in samples {
        let point = ImagePoint(x: try #require(sample["x"] as? Double), y: try #require(sample["y"] as? Double))
        let cell = map.cell(at: point)
        #expect(cell?.column == sample["column"] as? Int)
        #expect(cell?.row == sample["row"] as? Int)
        #expect(cell?.index == sample["index"] as? Int)
        #expect(map.isBlocked(at: point) == sample["blocked"] as? Bool)
    }
    try map.validateStart(at: ImagePoint(x: 100, y: 120))
    #expect(throws: FloorPlanValidationError.blockedStart) { try map.validateStart(at: ImagePoint(x: 220, y: 120)) }
    #expect(throws: FloorPlanValidationError.invalidCoordinate) { try map.validateStart(at: ImagePoint(x: 1000, y: 120)) }
}

@Test func coordinateConversionsAndBoundarySemantics() throws {
    let a = try FloorPlanGeometry.imagePoint(from: NormalizedPoint(x: 0.1, y: 0.2), width: 1000, height: 600)
    #expect(a == ImagePoint(x: 100, y: 120))
    #expect(try FloorPlanGeometry.normalizedPoint(from: a, width: 1000, height: 600) == NormalizedPoint(x: 0.1, y: 0.2))
    let edge = try FloorPlanGeometry.imagePoint(from: NormalizedPoint(x: 1, y: 1), width: 1000, height: 600)
    #expect(edge == ImagePoint(x: 1000, y: 600))
    let map = try validate(fixture())
    #expect(map.cell(at: edge) == nil && map.isBlocked(at: edge))
    for point in [ImagePoint(x: .nan, y: 1), ImagePoint(x: .infinity, y: 1), ImagePoint(x: -1, y: 1)] {
        #expect(map.cell(at: point) == nil && map.isBlocked(at: point))
        #expect(throws: FloorPlanValidationError.invalidCoordinate) {
            try FloorPlanGeometry.normalizedPoint(from: point, width: 1000, height: 600)
        }
    }
    #expect(throws: FloorPlanValidationError.invalidCoordinate) {
        try FloorPlanGeometry.imagePoint(from: NormalizedPoint(x: 1.1, y: 0), width: 1000, height: 600)
    }
}

@Test func exactOriginalBytesAreHashedRatherThanReencodedJSON() throws {
    let input = try fixture()
    let modified = input.files.navigationMapJSON + Data(" \n".utf8)
    let files = FloorPlanFiles(imagePNG: input.files.imagePNG, navigationMapJSON: modified, resolvedMask: input.files.resolvedMask)
    #expect(throws: FloorPlanValidationError.integrityMismatch) {
        try validate(Input(files: files, reference: input.reference))
    }
    let reference = FloorPlanReference(floorPlanID: input.reference.floorPlanID,
        revisionID: input.reference.revisionID, navigationSHA256: FloorPlanJSON.sha256(modified))
    #expect(try validate(Input(files: files, reference: reference)).files.navigationMapJSON == modified)
}

@Test func referenceAndSessionBindingMustMatch() throws {
    let input = try fixture()
    let wrong = FloorPlanReference(floorPlanID: input.reference.floorPlanID,
        revisionID: UUID(), navigationSHA256: input.reference.navigationSHA256)
    #expect(throws: FloorPlanValidationError.referenceMismatch) { try validate(Input(files: input.files, reference: wrong)) }
    #expect(throws: FloorPlanValidationError.referenceMismatch) {
        try FloorPlanValidator(imageValidator: PNGFloorPlanImageValidator())
            .validate(files: input.files, reference: input.reference, expectedReference: wrong)
    }
    let otherMap = try changed { $0["floorPlanID"] = "55555555-5555-4555-8555-555555555555" }
    #expect(throws: FloorPlanValidationError.referenceMismatch) { try validate(otherMap) }
}

@Test func unsupportedFormatsAreExplicitErrors() throws {
    #expect(throws: FloorPlanValidationError.unsupportedSchema(2)) { try validate(changed { $0["schemaVersion"] = 2 }) }
    #expect(throws: FloorPlanValidationError.unsupportedCoordinateSystem("bottom-left")) {
        try validate(changed { $0["coordinateSystem"] = "bottom-left" })
    }
    #expect(throws: FloorPlanValidationError.unsupportedEncoding("bit-packed")) {
        try validate(changed { json in
            var grid = json["navigationGrid"] as! [String: Any]; grid["encoding"] = "bit-packed"; json["navigationGrid"] = grid
        })
    }
}

@Test(arguments: ["scale", "indoorOutline", "imageWidth", "manuallyReviewed", "navigationGrid", "extractionAlgorithmVersion"])
func missingAndNullRequiredFieldsAreRejected(field: String) throws {
    #expect(throws: FloorPlanValidationError.invalidManifest) { try validate(changed { $0.removeValue(forKey: field) }) }
    #expect(throws: FloorPlanValidationError.invalidManifest) { try validate(changed { $0[field] = NSNull() }) }
}

@Test func malformedAndOversizedManifestAreRejected() throws {
    for bytes in [Data("{".utf8), Data("[]".utf8), Data(repeating: 32, count: 1_048_577),
                  try #require("{\"schemaVersion\":1}".data(using: .utf16))] {
        #expect(throws: FloorPlanValidationError.invalidManifest) { try FloorPlanJSON.decodeManifest(bytes) }
    }
    #expect(throws: FloorPlanValidationError.invalidManifest) { try validate(changed { $0["imageWidth"] = "1000" }) }
    #expect(throws: FloorPlanValidationError.invalidManifest) { try validate(changed { $0["manuallyReviewed"] = false }) }
    #expect(throws: FloorPlanValidationError.invalidManifest) { try validate(changed { $0["imageSHA256"] = "ABC" }) }
}

@Test func additiveMetadataAndNewProducerVersionsRemainReadable() throws {
    let map = try validate(changed {
        $0["futureOptionalNote"] = "ignored"
        $0["extractionAlgorithmVersion"] = "another-producer-v99"
        $0["rasterizationVersion"] = 99
    })
    #expect(map.manifest.extractionAlgorithmVersion == "another-producer-v99")
}

@Test(arguments: [0, -1, 4097, Int.max])
func unreasonableImageDimensionsAreRejectedBeforeAllocation(width: Int) throws {
    #expect(throws: FloorPlanValidationError.invalidImage) { try validate(changed { $0["imageWidth"] = width }) }
}

@Test(arguments: [0, -1, 4097, Int.max])
func invalidGridDimensionsDoNotOverflow(columns: Int) throws {
    #expect(throws: FloorPlanValidationError.invalidGrid) {
        try validate(changed { json in
            var grid = json["navigationGrid"] as! [String: Any]; grid["columns"] = columns; json["navigationGrid"] = grid
        })
    }
}

@Test func gridLengthValueAndOutsideRulesAreEnforced() throws {
    var mask = try fixture().files.resolvedMask
    #expect(throws: FloorPlanValidationError.invalidGrid) { try validate(changed(mask: mask.dropLast())) }
    mask[30050] = 2
    #expect(throws: FloorPlanValidationError.invalidGrid) { try validate(changed(mask: mask)) }
    mask[30050] = 0; mask[0] = 0
    #expect(throws: FloorPlanValidationError.invalidGrid) { try validate(changed(mask: mask)) }
    #expect(throws: FloorPlanValidationError.invalidGrid) {
        try validate(changed { json in
            var grid = json["navigationGrid"] as! [String: Any]; grid["outsideIsBlocked"] = false; json["navigationGrid"] = grid
        })
    }
    #expect(throws: FloorPlanValidationError.invalidGrid) {
        try validate(changed { json in
            var grid = json["navigationGrid"] as! [String: Any]; grid["cellSizePixels"] = 0; json["navigationGrid"] = grid
        })
    }
}

@Test func fileCorruptionCannotBeHiddenByRehashing() throws {
    let input = try fixture()
    var corruptMask = input.files.resolvedMask; corruptMask[0] ^= 1
    let badFiles = FloorPlanFiles(imagePNG: input.files.imagePNG, navigationMapJSON: input.files.navigationMapJSON, resolvedMask: corruptMask)
    #expect(throws: FloorPlanValidationError.integrityMismatch) { try validate(Input(files: badFiles, reference: input.reference)) }
    var png = input.files.imagePNG; png[30] ^= 1 // Damages the IHDR CRC.
    #expect(throws: FloorPlanValidationError.invalidImage) { try validate(changed(image: png)) }
    #expect(throws: FloorPlanValidationError.invalidImage) { try validate(changed(image: Data([1, 2, 3]))) }
    #expect(throws: FloorPlanValidationError.invalidImage) { try validate(changed(image: input.files.imagePNG.dropLast(12))) }
}

@Test(arguments: [0.0, -1.0, 1000.1, Double.leastNonzeroMagnitude, Double.infinity, Double.nan])
func invalidScaleDistancesAreRejected(meters: Double) throws {
    #expect(throws: FloorPlanValidationError.invalidScale) {
        try FloorPlanGeometry.pixelsPerMeter(for: MapScale(a: ImagePoint(x: 0, y: 0),
            b: ImagePoint(x: 10, y: 0), meters: meters), width: 1000, height: 600)
    }
}

@Test func minimumScaleDistanceAndBoundaryArePreserved() throws {
    #expect(throws: FloorPlanValidationError.invalidScale) {
        try validate(changed { $0["scale"] = ["a": ["x": 100, "y": 120], "b": ["x": 109, "y": 120], "meters": 1] })
    }
    let scale = MapScale(a: ImagePoint(x: 990, y: 600), b: ImagePoint(x: 1000, y: 600), meters: 1000)
    #expect(try FloorPlanGeometry.pixelsPerMeter(for: scale, width: 1000, height: 600) == 0.01)
}

@Test func malformedOutlinesAreRejected() throws {
    let invalid: [[[String: Double]]] = [
        [], [["x": 0, "y": 0], ["x": 1, "y": 1]],
        [["x": 0, "y": 0], ["x": 0.5, "y": 0.5], ["x": 1, "y": 1]],
        [["x": 0, "y": 0], ["x": 1, "y": 1], ["x": 0, "y": 1], ["x": 1, "y": 0]],
        [["x": 0, "y": 0], ["x": 0, "y": 0], ["x": 1, "y": 1]],
        [["x": -0.1, "y": 0], ["x": 1, "y": 0], ["x": 1, "y": 1]],
        Array(repeating: ["x": 0, "y": 0], count: 513)
    ]
    for outline in invalid {
        #expect(throws: FloorPlanValidationError.invalidOutline) { try validate(changed { $0["indoorOutline"] = outline }) }
    }
}

@Test func writerProducesLowercaseIDsAndPreservesSemanticRoundTrip() throws {
    let manifest = try FloorPlanJSON.decodeManifest(fixture().files.navigationMapJSON)
    let encoded = try FloorPlanJSON.encodeManifest(manifest)
    #expect(try FloorPlanJSON.decodeManifest(encoded) == manifest)
    let ids = FloorPlanReference(floorPlanID: try #require(UUID(uuidString: "ABCDEFAB-ABCD-4ABC-8ABC-ABCDEFABCDEF")),
        revisionID: manifest.revisionID, navigationSHA256: "a")
    let referenceJSON = try #require(String(data: JSONEncoder().encode(ids), encoding: .utf8))
    #expect(referenceJSON.contains("abcdefab-abcd-4abc-8abc-abcdefabcdef"))
    // Round-trip equality is semantic, not a promise of identical original bytes.
    #expect(encoded != (try fixture().files.navigationMapJSON))
}

@Test func cancellationRemainsCancellation() async throws {
    let input = try fixture()
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try validate(input)
    }
    do { _ = try await task.value; Issue.record("Expected cancellation") }
    catch is CancellationError { }
    catch { Issue.record("Unexpected cancellation mapping: \(error)") }
}

private func makePNG(width: Int, height: Int, alpha: UInt8 = 255) throws -> Data {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = alpha }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
        bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

@Test func imageAdapterRejectsMismatchedSizeAndTransparentPixels() throws {
    let adapter = PNGFloorPlanImageValidator()
    #expect(throws: FloorPlanValidationError.invalidImage) {
        try adapter.validatePNG(NormalFloorPlanFixture.data(for: .image), width: 999, height: 600)
    }
    #expect(throws: FloorPlanValidationError.invalidImage) { try adapter.validatePNG(makePNG(width: 10, height: 10, alpha: 0), width: 10, height: 10) }
    #expect(throws: FloorPlanValidationError.invalidImage) { try validate(changed(image: makePNG(width: 10, height: 10))) }
}

@Test func oddImageEdgeAndOutlineBoundaryCellUseExistingPolicy() throws {
    let image = try makePNG(width: 101, height: 81)
    var mask = Data(repeating: 0, count: 51 * 41)
    for row in 0..<41 { mask[row * 51 + 50] = 1 }
    for column in 0..<51 { mask[40 * 51 + column] = 1 }
    let input = try changed(image: image, mask: mask) { json in
        json["imageWidth"] = 101; json["imageHeight"] = 81
        json["scale"] = ["a": ["x": 10, "y": 10], "b": ["x": 30, "y": 10], "meters": 1]
        json["indoorOutline"] = [["x": 0, "y": 0], ["x": 1, "y": 0], ["x": 1, "y": 1], ["x": 0, "y": 1]]
        var grid = json["navigationGrid"] as! [String: Any]
        grid["columns"] = 51; grid["rows"] = 41; json["navigationGrid"] = grid
    }
    let map = try validate(input)
    #expect(map.cell(at: ImagePoint(x: 100, y: 80))?.index == 2090)
    #expect(map.isBlocked(at: ImagePoint(x: 100, y: 80)))
    #expect(!map.isBlocked(at: ImagePoint(x: 99, y: 79)))
    let boundaryMap = try validate(changed {
        $0["indoorOutline"] = [["x": 0.021, "y": 21.0 / 600], ["x": 0.979, "y": 21.0 / 600],
                              ["x": 0.979, "y": 579.0 / 600], ["x": 0.021, "y": 579.0 / 600]]
    })
    #expect(!boundaryMap.isBlocked(at: ImagePoint(x: 21, y: 21)))
}
