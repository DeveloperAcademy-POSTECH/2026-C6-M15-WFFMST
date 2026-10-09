import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
enum FloorPlanImportChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("floorplan-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = LocalFloorPlanImportService()
        let plan = try makeImage(width: 101, height: 81) { x, y in
            let wall = (10..<70).contains(x) && (8..<16).contains(y) && !(38..<46).contains(x)
            return wall ? [0, 0, 0, 255] : [255, 255, 255, 255]
        }
        let png = try write(plan, to: directory.appendingPathComponent("asymmetric.png"), type: .png)
        let imported = try await service.process(url: png)
        precondition(imported.image.width == 101 && imported.image.height == 81)
        precondition(imported.baseGrid.columns == 51 && imported.baseGrid.rows == 41)
        precondition(cell(imported, x: 20, y: 12) == 1, "top wall must remain at top")
        precondition(cell(imported, x: 20, y: 68) == 0, "bitmap must not vertically flip")
        precondition(cell(imported, x: 42, y: 12) == 0, "door opening must stay open")
        precondition(imported.baseGrid.blocked.allSatisfy { $0 <= 1 })
        let pngSource = CGImageSourceCreateWithData(imported.image.pngData as CFData, nil)!
        precondition(CGImageSourceGetType(pngSource) as String? == UTType.png.identifier)

        let transparent = try makeImage(width: 51, height: 51) { _, _ in [0, 0, 0, 0] }
        let alphaURL = try write(transparent, to: directory.appendingPathComponent("transparent.png"), type: .png)
        let alphaResult = try await service.process(url: alphaURL)
        precondition(alphaResult.baseGrid.blocked.allSatisfy { $0 == 0 }, "transparent background must become white")

        let jpeg = try write(plan, to: directory.appendingPathComponent("rotated.jpg"), type: .jpeg, orientation: 6)
        let rotated = try await service.process(url: jpeg)
        precondition(rotated.image.width == 81 && rotated.image.height == 101, "EXIF rotation must be applied")
        precondition(cell(rotated, x: 68, y: 20) == 1, "rotation must move top wall to right")
        precondition(cell(rotated, x: 12, y: 20) == 0, "rotation must not mirror wall")

        let wide = try makeImage(width: 4_200, height: 50) { _, _ in [255, 255, 255, 255] }
        let wideURL = try write(wide, to: directory.appendingPathComponent("wide.png"), type: .png)
        let reduced = try await service.process(url: wideURL)
        precondition(reduced.image.width == 4_096 && reduced.image.height <= 50)

        let gif = try write(plan, to: directory.appendingPathComponent("disguised.png"), type: .gif)
        do { _ = try await service.process(url: gif); fatalError("GIF must be rejected by content type") }
        catch is LocalFloorPlanError {}
        let corrupt = directory.appendingPathComponent("corrupt.png")
        try Data([1, 2, 3, 4]).write(to: corrupt)
        do { _ = try await service.process(url: corrupt); fatalError("corrupt image must fail") }
        catch is LocalFloorPlanError {}
        let tooLarge = directory.appendingPathComponent("large.png")
        FileManager.default.createFile(atPath: tooLarge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tooLarge)
        try handle.truncate(atOffset: 40 * 1_024 * 1_024 + 1)
        try handle.close()
        do { _ = try await service.process(url: tooLarge); fatalError("oversized file must fail") }
        catch is LocalFloorPlanError {}

        let cancelled = Task { try await service.process(url: png) }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("cancelled import must not succeed") }
        catch is CancellationError {}
        let started = ContinuousClock.now
        let detector = Task.detached {
            try LocalV13WallDetector.grid(rgba: [UInt8](repeating: 0, count: 4_096 * 4_096 * 4), width: 4_096, height: 4_096)
        }
        try await Task.sleep(for: .milliseconds(50))
        detector.cancel()
        do { _ = try await detector.value; fatalError("running detector must cooperate with cancellation") }
        catch is CancellationError {}
        precondition(started.duration(to: .now) < .seconds(3), "cancellation must be bounded")
        print("PASS: Import PNG/JPEG, orientation, alpha, downsample, V13 doors, ceil grid, errors, cancellation")
    }

    static func cell(_ result: LocalExtractionResult, x: Int, y: Int) -> UInt8 {
        result.baseGrid.blocked[(y / 2) * result.baseGrid.columns + x / 2]
    }

    static func makeImage(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) throws -> CGImage {
        var data = [UInt8]()
        data.reserveCapacity(width * height * 4)
        for y in 0..<height { for x in 0..<width { data.append(contentsOf: pixel(x, y)) } }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    @discardableResult
    static func write(_ image: CGImage, to url: URL, type: UTType, orientation: Int = 1) throws -> URL {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LocalFloorPlanError.invalid("Test image encode failed") }
        return url
    }
}
