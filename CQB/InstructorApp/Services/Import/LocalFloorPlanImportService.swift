import Foundation
import CoreGraphics
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Core ML 벽 분할 모델을 사용하는 앱 내부 입력 경계.
struct LocalFloorPlanImportService: FloorPlanImporting {
    nonisolated private static let logger = Logger(
        subsystem: "com.wffmst.cqb",
        category: "FloorPlanImport"
    )

    nonisolated init() {}

    nonisolated func normalize(url: URL) async throws -> LocalImportedImage {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Self.loadAndNormalize(url: url)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated func extractMask(from image: LocalImportedImage) async throws -> LocalMaskExtractionResult {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            let source = try Self.decodedSource(from: image)
            let extractionStart = ContinuousClock.now
            let grid = try LocalAIWallDetector.grid(
                image: source.image,
                sourceWidth: image.width,
                sourceHeight: image.height
            )
            let suggestion = try LocalBlockedRegionAutoFill.suggest(
                base: grid,
                rgba: source.pixels,
                width: image.width,
                height: image.height
            )
            Self.logDuration("ai-wall-extraction", since: extractionStart)
            return LocalMaskExtractionResult(
                baseGrid: grid,
                suggestedOutline: suggestion?.outline ?? [],
                extractionAlgorithm: .binaryCoreML
            )
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated func extractFallbackMask(from image: LocalImportedImage) async throws -> LocalMaskExtractionResult {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            let source = try Self.decodedSource(from: image)
            let extractionStart = ContinuousClock.now
            let grid = try LocalV13WallDetector.grid(
                rgba: source.pixels,
                width: image.width,
                height: image.height
            )
            let suggestion = try LocalBlockedRegionAutoFill.suggest(
                base: grid,
                rgba: source.pixels,
                width: image.width,
                height: image.height
            )
            Self.logDuration("v13-wall-extraction-fallback", since: extractionStart)
            return LocalMaskExtractionResult(
                baseGrid: grid,
                suggestedOutline: suggestion?.outline ?? [],
                extractionAlgorithm: .v13
            )
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func loadAndNormalize(url: URL) throws -> LocalImportedImage {
        try Task.checkCancellation()
        guard url.isFileURL else {
            throw LocalFloorPlanError.invalid("로컬 PNG 또는 JPEG 파일을 선택해 주세요.")
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let readStart = ContinuousClock.now
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
        logDuration("file-read", since: readStart)
        try Task.checkCancellation()
        let normalizationStart = ContinuousClock.now
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
        let cellSize = LocalV13WallDetector.cellSizePixels
        let width = (thumbnail.width + cellSize - 1) / cellSize * cellSize
        let height = (thumbnail.height + cellSize - 1) / cellSize * cellSize
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let image = pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Keep the source pixels at the top-left; only pad the right and bottom.
            // CGContext's drawing origin is bottom-left. Do not scale or flip the image.
            context.draw(thumbnail, in: CGRect(x: 0, y: height - thumbnail.height,
                width: thumbnail.width, height: thumbnail.height))
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
        logDuration("normalization", since: normalizationStart)
        return LocalImportedImage(
            pngData: output as Data,
            width: width,
            height: height,
            fileName: url.lastPathComponent
        )
    }

    nonisolated private static func decodedSource(
        from imported: LocalImportedImage
    ) throws -> (image: CGImage, pixels: [UInt8]) {
        guard imported.width > 0, imported.height > 0,
              let source = CGImageSourceCreateWithData(imported.pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == imported.width, image.height == imported.height else {
            throw LocalFloorPlanError.invalid("정규화된 도면 이미지를 읽지 못했습니다.")
        }
        var pixels = [UInt8](repeating: 255, count: imported.width * imported.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: bytes.baseAddress,
                    width: imported.width,
                    height: imported.height,
                    bitsPerComponent: 8,
                    bytesPerRow: imported.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: imported.width, height: imported.height))
            return true
        }
        guard rendered else {
            throw LocalFloorPlanError.invalid("정규화된 도면 픽셀을 읽지 못했습니다.")
        }
        return (image, pixels)
    }

    nonisolated private static func logDuration(_ stage: String, since start: ContinuousClock.Instant) {
#if DEBUG
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000
            + Double(duration.attoseconds) / 1_000_000_000_000_000
        logger.debug("stage=\(stage, privacy: .public) duration_ms=\(milliseconds, privacy: .public)")
#endif
    }
}
