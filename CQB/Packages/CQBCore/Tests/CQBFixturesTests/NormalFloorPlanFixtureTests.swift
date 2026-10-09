import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import CQBFixtures

// Test-only readers, not a second production data contract. The real CQBCore
// decoder/validator will consume these same files in the next implementation step.
private struct Expectations: Decodable {
    struct Point: Decodable { let x: Double; let y: Double }
    struct Sample: Decodable {
        let name: String
        let x: Double
        let y: Double
        let column: Int?
        let row: Int?
        let index: Int?
        let blocked: Bool
    }
    struct Session: Decodable { let sessionID: UUID; let floorPlan: Reference }
    let imageWidth: Int
    let imageHeight: Int
    let columns: Int
    let rows: Int
    let cellSizePixels: Int
    let pixelsPerMeter: Double
    let metersPerCell: Double
    let maskByteCount: Int
    let blockedCellCount: Int
    let freeCellCount: Int
    let scaleNormalizedA: Point
    let scaleNormalizedB: Point
    let samples: [Sample]
    let sessions: [Session]
}

private struct Reference: Decodable, Equatable {
    let floorPlanID: UUID
    let revisionID: UUID
    let navigationSHA256: String
}

private func expectations() throws -> Expectations {
    try JSONDecoder().decode(Expectations.self, from: NormalFloorPlanFixture.data(for: .expectations))
}
private func manifest() throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: NormalFloorPlanFixture.data(for: .manifest)) as? [String: Any])
}
private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Test func bundleContainsAllNormalFixtureFiles() throws {
    for file in NormalFloorPlanFixture.File.allCases {
        #expect(try !NormalFloorPlanFixture.data(for: file).isEmpty)
    }
}

@Test func manifestAndExactFileHashesAgree() throws {
    let metadata = try manifest()
    let reference = try JSONDecoder().decode(Reference.self, from: NormalFloorPlanFixture.data(for: .reference))
    let grid = try #require(metadata["navigationGrid"] as? [String: Any])
    #expect(metadata["schemaVersion"] as? Int == 1)
    #expect(metadata["coordinateSystem"] as? String == "image-top-left-row-major")
    #expect(metadata["manuallyReviewed"] as? Bool == true)
    #expect(metadata["extractionAlgorithmVersion"] as? String == "synthetic-normal-v1")
    #expect(metadata["rasterizationVersion"] as? Int == 2)
    #expect(metadata["navigationSHA256"] == nil)
    #expect(metadata["floorPlanID"] as? String == reference.floorPlanID.uuidString.lowercased())
    #expect(metadata["revisionID"] as? String == reference.revisionID.uuidString.lowercased())
    #expect(try hash(NormalFloorPlanFixture.data(for: .manifest)) == reference.navigationSHA256)
    #expect(try hash(NormalFloorPlanFixture.data(for: .image)) == metadata["imageSHA256"] as? String)
    #expect(try hash(NormalFloorPlanFixture.data(for: .mask)) == grid["maskSHA256"] as? String)
    #expect(grid["encoding"] as? String == "uint8-row-major")
    #expect(grid["freeValue"] as? Int == 0)
    #expect(grid["blockedValue"] as? Int == 1)
    #expect(grid["outsideIsBlocked"] as? Bool == true)
}

@Test func scaleAndCoordinatesMatchHandCalculatedExpectations() throws {
    let expected = try expectations()
    let metadata = try manifest()
    #expect(metadata["imageWidth"] as? Int == expected.imageWidth)
    #expect(metadata["imageHeight"] as? Int == expected.imageHeight)
    let grid = try #require(metadata["navigationGrid"] as? [String: Any])
    #expect(grid["columns"] as? Int == expected.columns)
    #expect(grid["rows"] as? Int == expected.rows)
    #expect(grid["cellSizePixels"] as? Int == expected.cellSizePixels)
    let scale = try #require(metadata["scale"] as? [String: Any])
    let a = try #require(scale["a"] as? [String: Double])
    let b = try #require(scale["b"] as? [String: Double])
    let ax = try #require(a["x"]), ay = try #require(a["y"])
    let bx = try #require(b["x"]), by = try #require(b["y"])
    let meters = try #require(scale["meters"] as? Double)
    #expect(ax == expected.scaleNormalizedA.x * Double(expected.imageWidth))
    #expect(ay == expected.scaleNormalizedA.y * Double(expected.imageHeight))
    #expect(bx == expected.scaleNormalizedB.x * Double(expected.imageWidth))
    #expect(by == expected.scaleNormalizedB.y * Double(expected.imageHeight))
    #expect(hypot(bx - ax, by - ay) / meters == expected.pixelsPerMeter)
    #expect(Double(expected.cellSizePixels) / expected.pixelsPerMeter == expected.metersPerCell)

    let mask = try NormalFloorPlanFixture.data(for: .mask)
    for point in expected.samples {
        let inBounds = point.x >= 0 && point.y >= 0
            && point.x < Double(expected.imageWidth) && point.y < Double(expected.imageHeight)
        if !inBounds {
            #expect(point.column == nil && point.row == nil && point.index == nil)
            #expect(point.blocked, "Out-of-image sample must be blocked: \(point.name)")
            continue // Never clamp or index an out-of-range point.
        }
        let column = Int(floor(point.x / Double(expected.cellSizePixels)))
        let row = Int(floor(point.y / Double(expected.cellSizePixels)))
        let index = row * expected.columns + column
        #expect(column == point.column && row == point.row && index == point.index)
        #expect((mask[index] == 1) == point.blocked, "Unexpected cell: \(point.name)")
    }
}

@Test func wholeGridMatchesIndependentRectangleSpecification() throws {
    let mask = try NormalFloorPlanFixture.data(for: .mask)
    let expected = try expectations()
    #expect(mask.count == expected.maskByteCount)
    #expect(mask.count == expected.columns * expected.rows)
    #expect(mask.allSatisfy { $0 == 0 || $0 == 1 })
    #expect(mask.filter { $0 == 1 }.count == expected.blockedCellCount)
    #expect(mask.filter { $0 == 0 }.count == expected.freeCellCount)
    // Pixel-space rectangles are the human-authored spec. The generator instead
    // uses integer cell ranges. Do not call the generator to create this oracle.
    let solids = [CGRect(x: 200, y: 80, width: 40, height: 80),
                  CGRect(x: 600, y: 80, width: 10, height: 200),
                  CGRect(x: 600, y: 320, width: 10, height: 200),
                  CGRect(x: 800, y: 420, width: 60, height: 40)]
    let metadata = try manifest()
    let outline = try #require(metadata["indoorOutline"] as? [[String: Double]])
    let corners: [(Double, Double)] = [(20, 20), (980, 20), (980, 580), (20, 580)]
    #expect(outline.count == corners.count)
    for (point, corner) in zip(outline, corners) {
        #expect(abs(try #require(point["x"]) * 1000 - corner.0) < 1e-9)
        #expect(abs(try #require(point["y"]) * 600 - corner.1) < 1e-9)
    }
    for row in 0..<expected.rows {
        for column in 0..<expected.columns {
            let center = CGPoint(x: column * 2 + 1, y: row * 2 + 1)
            let outside = center.x < 20 || center.x > 980 || center.y < 20 || center.y > 580
            let blocked = outside || solids.contains { $0.contains(center) }
            // One aggregate failure avoids 150,000 successful assertion events.
            if (mask[row * expected.columns + column] == 1) != blocked {
                Issue.record("Grid mismatch at column \(column), row \(row)")
                return
            }
        }
    }
}

@Test func pngIsDecodableOpaqueAndAlignedWithGrid() throws {
    let bytes = try NormalFloorPlanFixture.data(for: .image)
    let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    #expect(CGImageSourceGetCount(source) == 1)
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let expected = try expectations()
    #expect(image.width == expected.imageWidth && image.height == expected.imageHeight)
    #expect(image.bitsPerComponent == 8)
    #expect(image.colorSpace?.name == CGColorSpace.sRGB)
    var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try rgba.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(data: buffer.baseAddress,
            width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let mask = try NormalFloorPlanFixture.data(for: .mask)
    for y in 0..<image.height {
        for x in 0..<image.width {
            let outside = x < 20 || x >= 980 || y < 20 || y >= 580
            let blocked = mask[(y / 2) * expected.columns + x / 2] == 1
            let value: UInt8 = outside ? 192 : blocked ? 0 : 255
            let i = (y * image.width + x) * 4
            if rgba[i] != value || rgba[i + 1] != value || rgba[i + 2] != value || rgba[i + 3] != 255 {
                Issue.record("PNG mismatch/flip/transparency at (\(x), \(y))")
                return
            }
        }
    }
}

@Test func twoSessionExamplesReuseTheSameExactReference() throws {
    let expected = try expectations()
    let reference = try JSONDecoder().decode(Reference.self, from: NormalFloorPlanFixture.data(for: .reference))
    #expect(expected.sessions.count == 2)
    #expect(Set(expected.sessions.map(\.sessionID)).count == 2)
    #expect(expected.sessions.allSatisfy { $0.floorPlan == reference })
    // This proves fixture consistency, not repository immutability or auth.
}
