import CQBCore
import CQBFirebase
import UIKit
import XCTest
@testable import InstructorApp

@MainActor
final class TransparentFloorPlanTests: XCTestCase {
    func testImportAndStorageRoundTripPreserveAlpha() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alpha-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(makeImage().pngData()).write(to: url)
        let imported = try await LocalFloorPlanImportService().normalize(url: url)
        try assertAlpha(imported.pngData)
        let registration = makeRegistration(image: imported)
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let catalog = InstructorFloorPlan(id: registration.id.uuidString, name: registration.name,
                                         fileName: imported.fileName, referenceDistance: 10,
                                         reference: upload.reference)
        // Exercise the file boundary, rather than reusing the in-memory registration.
        let fileURL = url.deletingLastPathComponent().appendingPathComponent("stored-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try upload.files.imagePNG.write(to: fileURL)
        let files = FloorPlanFiles(imagePNG: try Data(contentsOf: fileURL),
                                  navigationMapJSON: upload.files.navigationMapJSON,
                                  resolvedMask: upload.files.resolvedMask)
        let restored = try LocalFloorPlanFileLoader.load(files: files, reference: upload.reference, catalog: catalog)
        XCTAssertEqual(restored.registration.image.pngData, imported.pngData)
        try assertAlpha(restored.registration.image.pngData)
    }

    func testStorageEmulatorRoundTripPreservesAlpha() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CQB_FIREBASE_EMULATOR_TESTS"] == "1",
              environment["FIREBASE_EMULATOR_HOST"] == "127.0.0.1" else {
            throw XCTSkip("Requires explicit opt-in and the local Firebase emulator")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("emulator-alpha-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(makeImage().pngData()).write(to: url)
        let imported = try await LocalFloorPlanImportService().normalize(url: url)
        let registration = makeRegistration(image: imported)
        let upload = try LocalFloorPlanFileBuilder.build(from: registration)
        let repository = StorageFloorPlanFileRepository()
        try await repository.upload(upload.files, for: upload.reference)
        let downloaded = try await repository.download(upload.reference)
        XCTAssertEqual(downloaded.imagePNG, imported.pngData)
        XCTAssertEqual(downloaded.navigationMapJSON, upload.files.navigationMapJSON)
        XCTAssertEqual(downloaded.resolvedMask, upload.files.resolvedMask)
        try assertAlpha(downloaded.imagePNG)
        let catalog = InstructorFloorPlan(id: registration.id.uuidString, name: registration.name,
                                         fileName: imported.fileName, referenceDistance: 10,
                                         reference: upload.reference)
        let restored = try LocalFloorPlanFileLoader.load(files: downloaded, reference: upload.reference, catalog: catalog)
        try assertAlpha(restored.registration.image.pngData)
    }

    func testDownsampledPreviewPreservesTransparentAndSemitransparentRegions() throws {
        let preview = try LocalFloorPlanListPreviewRenderer.render(
            imagePNG: XCTUnwrap(makeImage().pngData()), maximumPixelSize: 32
        )
        let image = try XCTUnwrap(UIImage(data: preview.imagePNGData)?.cgImage)
        XCTAssertEqual(image.width, 32)
        let pixels = rgba(image)
        XCTAssertEqual(pixels[(8 * 32 + 4) * 4 + 3], 0)
        XCTAssertEqual(Int(pixels[(8 * 32 + 16) * 4 + 3]), 128, accuracy: 1)
        XCTAssertEqual(pixels[(8 * 32 + 28) * 4 + 3], 255)
    }

    func testCanvasAndToneOverlayLeaveTransparentRegionClear() throws {
        let image = makeImage()
        let view = LocalFloorPlanCanvasView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        defer { view.tearDown() }
        for transparentBackground in [false, true] {
            view.update(image: image, mask: nil, tool: .move, normalizedDiameter: 0.02,
                        selection: [], pendingBrushStrokes: [], scaleA: nil, scaleB: nil, scaleLabel: nil,
                        scaleALabel: "A", scaleBLabel: "B", scaleMarkerAppearance: .standard,
                        showsScanStartSelection: false, usesTransparentBackground: transparentBackground,
                        maximumInitialDisplaySize: nil, imageToneOverlayOpacity: 0.2,
                        checkpointMarkers: [], checkpointAppearance: .labeled)
            view.layoutIfNeeded()
            let scroll = try XCTUnwrap(view.subviews.compactMap { $0 as? UIScrollView }.first)
            let content = try XCTUnwrap(view.viewForZooming(in: scroll))
            XCTAssertEqual(content.backgroundColor, transparentBackground ? .clear : .white)
            XCTAssertEqual(content.isOpaque, !transparentBackground)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let rendered = UIGraphicsImageRenderer(size: content.bounds.size, format: format).image {
                content.layer.render(in: $0.cgContext)
            }
            let pixels = rgba(try XCTUnwrap(rendered.cgImage))
            XCTAssertEqual(pixels[(16 * 64 + 8) * 4 + 3], transparentBackground ? 0 : 255,
                           "Transparent canvases must stay clear; the detail canvas retains its original white background")
            XCTAssertEqual(pixels[(16 * 64 + 56) * 4 + 3], 255)
        }
    }

    private func makeRegistration(image: LocalImportedImage) -> LocalRegisteredFloorPlan {
        let grid = LocalObstacleGrid(columns: image.width / 2, rows: image.height / 2, cellSizePixels: 2,
                                     blocked: [UInt8](repeating: 0, count: image.width / 2 * (image.height / 2)))
        return LocalRegisteredFloorPlan(
            id: UUID(), name: "투명 도면", image: image, baseGrid: grid, edits: [],
            outline: [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1), .init(x: 0, y: 1)],
            scale: LocalPlanScale(a: .init(x: 0, y: 0.5), b: .init(x: 1, y: 0.5), meters: 10),
            resolvedGrid: grid, extractionAlgorithm: .v13
        )
    }

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor.black.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: 24, y: 0, width: 16, height: 64))
            UIColor.black.setFill()
            context.fill(CGRect(x: 48, y: 0, width: 16, height: 64))
        }
    }

    private func assertAlpha(_ data: Data) throws {
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)
        let pixels = rgba(image)
        XCTAssertEqual(pixels[(16 * 64 + 8) * 4 + 3], 0)
        XCTAssertEqual(Int(pixels[(16 * 64 + 32) * 4 + 3]), 128, accuracy: 1)
        XCTAssertEqual(pixels[(16 * 64 + 56) * 4 + 3], 255)
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                        | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
