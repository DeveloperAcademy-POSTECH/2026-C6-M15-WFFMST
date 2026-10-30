import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct LocalObstacleGrid {
    let columns: Int
    let rows: Int
    let cellSizePixels: Int
    let blocked: [UInt8]
}

enum LocalFloorPlanError: Error {
    case invalid(String)
}

enum LocalV13WallDetector {
    static let cellSizePixels = 2
}

@main
struct CoreMLPostprocessExperiment {
    private struct Arguments {
        let output: URL
        let minimumComponentArea: Int
        let maximumHoleArea: Int
        let maximumChangedFraction: Double
        let minimumAxisAlignedLength: Int
        let maximumAxisAlignedThickness: Int
        let maximumAxisAlignedSnapDistance: Int
        let inputs: [URL]
    }

    private struct ImageMetrics: Codable {
        let fileName: String
        let normalizedImage: String
        let rawMask: String
        let processedMask: String
        let columns: Int
        let rows: Int
        let rawBlockedCells: Int
        let processedBlockedCells: Int
        let removedComponentCount: Int
        let removedCellCount: Int
        let filledHoleCount: Int
        let addedCellCount: Int
        let straightenedBandCount: Int
        let straightenedAddedCellCount: Int
        let straightenedRemovedCellCount: Int
        let changeBudgetCells: Int
        let changedFraction: Double
        let inferenceMilliseconds: Double
        let postprocessMilliseconds: Double
    }

    private struct Manifest: Codable {
        let minimumComponentAreaCells: Int
        let maximumHoleAreaCells: Int
        let maximumChangedFraction: Double
        let minimumAxisAlignedLengthCells: Int
        let maximumAxisAlignedThicknessCells: Int
        let maximumAxisAlignedSnapDistanceCells: Int
        let images: [ImageMetrics]
    }

    private struct NormalizedImage {
        let image: CGImage
        let pngData: Data
    }

    static func main() throws {
        let arguments = try parseArguments()
        try FileManager.default.createDirectory(
            at: arguments.output,
            withIntermediateDirectories: true
        )
        let configuration = LocalWallMaskPostprocessor.Configuration(
            minimumBlockedComponentAreaCells: arguments.minimumComponentArea,
            maximumHoleAreaCells: arguments.maximumHoleArea,
            maximumChangedFraction: arguments.maximumChangedFraction,
            minimumAxisAlignedLengthCells: arguments.minimumAxisAlignedLength,
            maximumAxisAlignedThicknessCells: arguments.maximumAxisAlignedThickness,
            maximumAxisAlignedSnapDistanceCells: arguments.maximumAxisAlignedSnapDistance
        )
        var imageMetrics: [ImageMetrics] = []

        for (index, input) in arguments.inputs.enumerated() {
            let normalized = try normalize(input)
            let inferenceStart = ContinuousClock.now
            let raw = try LocalAIWallDetector.grid(
                image: normalized.image,
                sourceWidth: normalized.image.width,
                sourceHeight: normalized.image.height
            )
            let inferenceMilliseconds = milliseconds(since: inferenceStart)
            let postprocessStart = ContinuousClock.now
            let processed = try LocalWallMaskPostprocessor.process(
                blocked: raw.blocked,
                columns: raw.columns,
                rows: raw.rows,
                configuration: configuration
            )
            let postprocessMilliseconds = milliseconds(since: postprocessStart)

            let stem = String(format: "%02d", index + 1)
            let imageName = "\(stem)-normalized.png"
            let rawMaskName = "\(stem)-raw.pgm"
            let processedMaskName = "\(stem)-processed.pgm"
            try normalized.pngData.write(to: arguments.output.appendingPathComponent(imageName))
            try writePGM(
                blocked: raw.blocked,
                columns: raw.columns,
                rows: raw.rows,
                to: arguments.output.appendingPathComponent(rawMaskName)
            )
            try writePGM(
                blocked: processed.blocked,
                columns: raw.columns,
                rows: raw.rows,
                to: arguments.output.appendingPathComponent(processedMaskName)
            )

            let changedCells = zip(raw.blocked, processed.blocked).reduce(into: 0) { count, pair in
                if pair.0 != pair.1 {
                    count += 1
                }
            }
            imageMetrics.append(ImageMetrics(
                fileName: input.lastPathComponent,
                normalizedImage: imageName,
                rawMask: rawMaskName,
                processedMask: processedMaskName,
                columns: raw.columns,
                rows: raw.rows,
                rawBlockedCells: raw.blocked.reduce(0) { $0 + Int($1) },
                processedBlockedCells: processed.blocked.reduce(0) { $0 + Int($1) },
                removedComponentCount: processed.metrics.removedComponentCount,
                removedCellCount: processed.metrics.removedCellCount,
                filledHoleCount: processed.metrics.filledHoleCount,
                addedCellCount: processed.metrics.addedCellCount,
                straightenedBandCount: processed.metrics.straightenedBandCount,
                straightenedAddedCellCount: processed.metrics.straightenedAddedCellCount,
                straightenedRemovedCellCount: processed.metrics.straightenedRemovedCellCount,
                changeBudgetCells: processed.metrics.changeBudgetCells,
                changedFraction: Double(changedCells) / Double(raw.blocked.count),
                inferenceMilliseconds: inferenceMilliseconds,
                postprocessMilliseconds: postprocessMilliseconds
            ))
            print(
                "\(input.lastPathComponent)\tinference_ms=\(inferenceMilliseconds)"
                    + "\tpostprocess_ms=\(postprocessMilliseconds)"
                    + "\tremoved=\(processed.metrics.removedCellCount)"
                    + "\tadded=\(processed.metrics.addedCellCount)"
                    + "\tstraightened=\(processed.metrics.straightenedBandCount)"
            )
        }

        let manifest = Manifest(
            minimumComponentAreaCells: arguments.minimumComponentArea,
            maximumHoleAreaCells: arguments.maximumHoleArea,
            maximumChangedFraction: arguments.maximumChangedFraction,
            minimumAxisAlignedLengthCells: arguments.minimumAxisAlignedLength,
            maximumAxisAlignedThicknessCells: arguments.maximumAxisAlignedThickness,
            maximumAxisAlignedSnapDistanceCells: arguments.maximumAxisAlignedSnapDistance,
            images: imageMetrics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: arguments.output.appendingPathComponent("metrics.json")
        )
    }

    private static func parseArguments() throws -> Arguments {
        var output: URL?
        var minimumComponentArea = 8
        var maximumHoleArea = 8
        var maximumChangedFraction = 0.005
        var minimumAxisAlignedLength = 0
        var maximumAxisAlignedThickness = 0
        var maximumAxisAlignedSnapDistance = 0
        var inputs: [URL] = []
        var index = 1
        while index < CommandLine.arguments.count {
            switch CommandLine.arguments[index] {
            case "--output":
                index += 1
                guard index < CommandLine.arguments.count else { throw LocalFloorPlanError.invalid(usage) }
                output = URL(fileURLWithPath: CommandLine.arguments[index], isDirectory: true)
            case "--minimum-component-area":
                index += 1
                guard index < CommandLine.arguments.count,
                      let value = Int(CommandLine.arguments[index]) else {
                    throw LocalFloorPlanError.invalid(usage)
                }
                minimumComponentArea = value
            case "--maximum-hole-area":
                index += 1
                guard index < CommandLine.arguments.count,
                      let value = Int(CommandLine.arguments[index]) else {
                    throw LocalFloorPlanError.invalid(usage)
                }
                maximumHoleArea = value
            case "--maximum-changed-fraction":
                index += 1
                guard index < CommandLine.arguments.count,
                      let value = Double(CommandLine.arguments[index]) else {
                    throw LocalFloorPlanError.invalid(usage)
                }
                maximumChangedFraction = value
            case "--minimum-axis-length":
                index += 1
                guard index < CommandLine.arguments.count,
                      let value = Int(CommandLine.arguments[index]) else {
                    throw LocalFloorPlanError.invalid(usage)
                }
                minimumAxisAlignedLength = value
            case "--maximum-axis-thickness":
                index += 1
                guard index < CommandLine.arguments.count,
                      let value = Int(CommandLine.arguments[index]) else {
                    throw LocalFloorPlanError.invalid(usage)
                }
                maximumAxisAlignedThickness = value
            case "--maximum-axis-snap-distance":
                index += 1
                guard index < CommandLine.arguments.count,
                      let value = Int(CommandLine.arguments[index]) else {
                    throw LocalFloorPlanError.invalid(usage)
                }
                maximumAxisAlignedSnapDistance = value
            case "--help", "-h":
                print(usage)
                Foundation.exit(EXIT_SUCCESS)
            default:
                inputs.append(URL(fileURLWithPath: CommandLine.arguments[index]))
            }
            index += 1
        }
        guard let output, !inputs.isEmpty else { throw LocalFloorPlanError.invalid(usage) }
        return Arguments(
            output: output,
            minimumComponentArea: minimumComponentArea,
            maximumHoleArea: maximumHoleArea,
            maximumChangedFraction: maximumChangedFraction,
            minimumAxisAlignedLength: minimumAxisAlignedLength,
            maximumAxisAlignedThickness: maximumAxisAlignedThickness,
            maximumAxisAlignedSnapDistance: maximumAxisAlignedSnapDistance,
            inputs: inputs
        )
    }

    private static var usage: String {
        """
        Usage: coreml-postprocess --output DIR [options] IMAGE...
          --minimum-component-area N     Remove interior blocked components smaller than N cells (default: 8)
          --maximum-hole-area N          Fill enclosed free components up to N cells (default: 8)
          --maximum-changed-fraction F   Cap all changed cells as a fraction of the grid (default: 0.005)
          --minimum-axis-length N        Straighten horizontal/vertical runs at least N cells long (default: off)
          --maximum-axis-thickness N     Maximum consecutive runs in a straightened band (default: off)
          --maximum-axis-snap-distance N Maximum endpoint movement in cells (default: off)
        """
    }

    private static func normalize(_ url: URL) throws -> NormalizedImage {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4_096,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary), thumbnail.width > 0, thumbnail.height > 0 else {
            throw LocalFloorPlanError.invalid("이미지를 읽지 못했습니다: \(url.path)")
        }
        let cellSize = LocalV13WallDetector.cellSizePixels
        let width = (thumbnail.width + cellSize - 1) / cellSize * cellSize
        let height = (thumbnail.height + cellSize - 1) / cellSize * cellSize
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let image = pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(
                thumbnail,
                in: CGRect(
                    x: 0,
                    y: height - thumbnail.height,
                    width: thumbnail.width,
                    height: thumbnail.height
                )
            )
            return context.makeImage()
        }
        guard let image else { throw LocalFloorPlanError.invalid("이미지를 정규화하지 못했습니다.") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw LocalFloorPlanError.invalid("PNG 출력을 만들지 못했습니다.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LocalFloorPlanError.invalid("PNG 출력을 저장하지 못했습니다.")
        }
        return NormalizedImage(image: image, pngData: output as Data)
    }

    private static func writePGM(
        blocked: [UInt8],
        columns: Int,
        rows: Int,
        to url: URL
    ) throws {
        var data = Data("P5\n\(columns) \(rows)\n255\n".utf8)
        data.append(contentsOf: blocked.map { $0 == 0 ? 0 : 255 })
        try data.write(to: url, options: .atomic)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) * 1_000
            + Double(duration.attoseconds) / 1_000_000_000_000_000
    }
}
