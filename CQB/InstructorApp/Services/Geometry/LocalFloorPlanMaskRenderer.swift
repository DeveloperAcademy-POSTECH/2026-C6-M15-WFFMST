import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum LocalFloorPlanMaskRenderer {
    /// Grid-resolution PNG, intended to be displayed with nearest-neighbor scaling.
    nonisolated static func pngData(grid: LocalObstacleGrid) throws -> Data {
        try LocalFloorPlanGeometry.validateGrid(grid)
        var rgba = [UInt8](repeating: 0, count: grid.blocked.count * 4)
        for index in grid.blocked.indices {
            if index % 16_384 == 0 { try Task.checkCancellation() }
            if grid.blocked[index] == 1 {
                rgba[index * 4] = 155
                rgba[index * 4 + 1] = 65
                rgba[index * 4 + 2] = 220
                rgba[index * 4 + 3] = 150
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: grid.columns, height: grid.rows,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: grid.columns * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            throw LocalFloorPlanError.invalid("장애물 미리보기를 생성하지 못했습니다.")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw LocalFloorPlanError.invalid("장애물 미리보기 형식을 생성하지 못했습니다.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LocalFloorPlanError.invalid("장애물 미리보기를 인코딩하지 못했습니다.")
        }
        try Task.checkCancellation()
        return data as Data
    }
}
