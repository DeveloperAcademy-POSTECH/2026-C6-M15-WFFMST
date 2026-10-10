import Foundation
import Testing
@testable import CQBCore

@Test("FloorPlanReference는 revision 없이 도면을 식별한다")
func floorPlanReferenceWithoutRevision() throws {
    let reference = FloorPlanReference(
        floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
        navigationSHA256: "navigation-sha256"
    )

    let decoded = try codableRoundTrip(reference)
    let json = try encodedJSONObject(reference)

    #expect(decoded == reference)
    #expect(json["navigationSHA256"] as? String == reference.navigationSHA256)
    #expect(json["revisionID"] == nil)
}

@Test("FloorPlanManifest가 좌표와 축척, 탐색 격자 정보를 보존한다")
func floorPlanManifestCodableRoundTrip() throws {
    let manifest = FloorPlanManifest(
        schemaVersion: 1,
        floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
        coordinateSystem: "image-pixel-top-left",
        imageWidth: 2_048,
        imageHeight: 1_536,
        imageSHA256: "image-sha256",
        scale: MapScale(
            a: ImagePoint(x: 100, y: 200),
            b: ImagePoint(x: 600, y: 200),
            meters: 5
        ),
        indoorOutline: [
            NormalizedPoint(x: 0.1, y: 0.1),
            NormalizedPoint(x: 0.9, y: 0.1),
            NormalizedPoint(x: 0.9, y: 0.9),
        ],
        navigationGrid: NavigationGridDescriptor(
            columns: 256,
            rows: 192,
            cellSizePixels: 8,
            encoding: "uint8-row-major",
            freeValue: 0,
            blockedValue: 1,
            outsideIsBlocked: true,
            maskSHA256: "mask-sha256"
        ),
        extractionAlgorithmVersion: "wall-extractor-1",
        rasterizationVersion: 1,
        manuallyReviewed: true
    )

    let decoded = try codableRoundTrip(manifest)
    let json = try encodedJSONObject(manifest)

    #expect(decoded == manifest)
    #expect(json["revisionID"] == nil)
}

@Test("FloorPlanFiles가 업로드할 파일 바이트를 그대로 보존한다")
func floorPlanFilesPreserveBytes() {
    let files = FloorPlanFiles(
        imagePNG: Data([0x89, 0x50, 0x4E, 0x47]),
        navigationMapJSON: Data("{}".utf8),
        resolvedMask: Data([0, 1, 1, 0])
    )

    #expect(files.imagePNG == Data([0x89, 0x50, 0x4E, 0x47]))
    #expect(files.navigationMapJSON == Data("{}".utf8))
    #expect(files.resolvedMask == Data([0, 1, 1, 0]))
}
