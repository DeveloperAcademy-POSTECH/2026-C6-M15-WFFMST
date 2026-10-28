import CoreGraphics
import Foundation
import ImageIO

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
struct CoreMLWallBatch {
    static func main() throws {
        guard CommandLine.arguments.count >= 3,
              (CommandLine.arguments.count - 1).isMultiple(of: 2) else {
            throw RunnerError.usage
        }
        for index in stride(from: 1, to: CommandLine.arguments.count, by: 2) {
            let started = ContinuousClock.now
            let inputURL = URL(fileURLWithPath: CommandLine.arguments[index])
            let outputURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw RunnerError.cannotReadImage(inputURL.path)
            }
            let grid = try LocalAIWallDetector.grid(
                image: image,
                sourceWidth: image.width,
                sourceHeight: image.height,
                configuration: .cropContrastTiles
            )
            try writePGM(grid: grid, to: outputURL)
            let elapsed = ContinuousClock.now - started
            print("\(inputURL.lastPathComponent)\t\(elapsed)")
        }
    }

    private static func writePGM(grid: LocalObstacleGrid, to url: URL) throws {
        var data = Data("P5\n\(grid.columns) \(grid.rows)\n255\n".utf8)
        data.append(contentsOf: grid.blocked.map { $0 == 0 ? 0 : 255 })
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    enum RunnerError: Error {
        case usage
        case cannotReadImage(String)
    }
}

