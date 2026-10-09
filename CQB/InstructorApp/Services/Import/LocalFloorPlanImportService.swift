import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// PoC V13 추출기를 사용하는 앱 내부 입력 경계. paleWalls 프로필은 이번 이관에서 제외한다.
struct LocalFloorPlanImportService: FloorPlanImporting {
    nonisolated init() {}

    nonisolated func process(url: URL) async throws -> LocalExtractionResult {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Self.loadAndExtract(url: url)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func loadAndExtract(url: URL) throws -> LocalExtractionResult {
        try Task.checkCancellation()
        guard url.isFileURL else {
            throw LocalFloorPlanError.invalid("로컬 PNG 또는 JPEG 파일을 선택해 주세요.")
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let maximumBytes = 40 * 1_024 * 1_024
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw LocalFloorPlanError.invalid("40MB 이하의 PNG 또는 JPEG 파일을 선택해 주세요.")
        }
        // Bounded read also protects against a file growing after the resource-value check.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let input = try handle.read(upToCount: maximumBytes + 1), input.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(input as CFData, nil),
              let type = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type as String) else {
            throw LocalFloorPlanError.invalid("PNG 또는 JPEG 이미지를 읽지 못했습니다.")
        }
        try Task.checkCancellation()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4_096,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              thumbnail.width > 0, thumbnail.height > 0 else {
            throw LocalFloorPlanError.invalid("이미지를 변환하지 못했습니다.")
        }
        try Task.checkCancellation()
        let width = thumbnail.width
        let height = thumbnail.height
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let image = pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // CGImage bitmap rows already match the top-left image coordinates. Do not flip.
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }
        guard let image else { throw LocalFloorPlanError.invalid("도면 픽셀을 읽지 못했습니다.") }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw LocalFloorPlanError.invalid("도면 이미지를 변환하지 못했습니다.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LocalFloorPlanError.invalid("도면 이미지를 변환하지 못했습니다.")
        }
        try Task.checkCancellation()
        let grid = try LocalV13WallDetector.grid(rgba: pixels, width: width, height: height)
        return LocalExtractionResult(
            image: LocalImportedImage(pngData: output as Data, width: width, height: height, fileName: url.lastPathComponent),
            baseGrid: grid)
    }
}
