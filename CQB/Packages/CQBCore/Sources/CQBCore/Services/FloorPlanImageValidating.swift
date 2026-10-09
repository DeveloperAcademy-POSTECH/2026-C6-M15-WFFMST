import Foundation

/// Trusted image-decoder boundary. Must reject undecodable, non-normalized,
/// non-opaque, non-sRGB/8-bit/static PNGs or dimensions differing from the manifest.
/// Must not modify the bytes. Implementations must cooperate with cancellation.
public protocol FloorPlanImageValidating: Sendable {
    func validatePNG(_ data: Data, width: Int, height: Int) throws
}
