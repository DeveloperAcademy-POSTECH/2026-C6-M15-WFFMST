import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CQBCore

/// Image I/O adapter, shared by both Apple-platform apps without exposing
/// CoreGraphics/ImageIO/SwiftUI types in CQBCore's data contract.
public struct PNGFloorPlanImageValidator: FloorPlanImageValidating {
    public init() {}

    public func validatePNG(_ data: Data, width: Int, height: Int) throws {
        try Task.checkCancellation()
        guard (1...4_096).contains(width), (1...4_096).contains(height) else {
            throw FloorPlanValidationError.invalidImage
        }
        try validateContainer(data)
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1, CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == width,
              properties[kCGImagePropertyPixelHeight] as? Int == height,
              (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1 else {
            throw FloorPlanValidationError.invalidImage
        }
        // Dimensions are checked BEFORE full decode/allocation; no thumbnail
        // or orientation repair is performed on already-normalized contract data.
        try Task.checkCancellation()
        guard let image = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              image.width == width, image.height == height, image.bitsPerComponent == 8,
              image.colorSpace?.name == CGColorSpace.sRGB,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw FloorPlanValidationError.invalidImage
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        try rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw FloorPlanValidationError.invalidImage
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        for row in 0..<height {
            try Task.checkCancellation()
            for column in 0..<width where rgba[(row * width + column) * 4 + 3] != 255 {
                throw FloorPlanValidationError.invalidImage
            }
        }
    }

    // ImageIO may tolerate damaged ancillary chunks. Check framing/CRC as well,
    // so a rehashed truncated/corrupt PNG is not silently accepted as a valid map.
    private func validateContainer(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count >= 8, Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else {
                throw FloorPlanValidationError.invalidImage
            }
            func uint32(_ offset: Int) -> UInt32 {
                (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
                    | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
            }
            var offset = 8, hasImageData = false, hasEnd = false
            while offset < bytes.count {
                try Task.checkCancellation()
                guard bytes.count - offset >= 12 else { throw FloorPlanValidationError.invalidImage }
                let length = Int(uint32(offset))
                guard length <= bytes.count - offset - 12 else { throw FloorPlanValidationError.invalidImage }
                let type = uint32(offset + 4)
                if offset == 8 {
                    guard type == 0x49484452, length == 13 else { throw FloorPlanValidationError.invalidImage } // IHDR
                } else if type == 0x49484452 { throw FloorPlanValidationError.invalidImage }
                guard type != 0x6163544c else { throw FloorPlanValidationError.invalidImage } // acTL: no APNG
                var crc: UInt32 = 0xffffffff
                for i in (offset + 4)..<(offset + 8 + length) {
                    if i % 65_536 == 0 { try Task.checkCancellation() }
                    crc = Self.crcTable[Int((crc ^ UInt32(bytes[i])) & 255)] ^ (crc >> 8)
                }
                guard (crc ^ 0xffffffff) == uint32(offset + 8 + length) else {
                    throw FloorPlanValidationError.invalidImage
                }
                offset += length + 12
                if type == 0x49444154 { hasImageData = true } // IDAT
                if type == 0x49454e44 { // IEND
                    guard length == 0, offset == bytes.count else { throw FloorPlanValidationError.invalidImage }
                    hasEnd = true
                }
            }
            guard hasImageData, hasEnd else { throw FloorPlanValidationError.invalidImage }
        }
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        return crc
    }
}
