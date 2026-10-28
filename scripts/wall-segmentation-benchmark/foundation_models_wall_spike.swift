import Foundation
import FoundationModels

@available(macOS 27.0, *)
@Generable
struct WallSegment: Codable {
    var x1: Int
    var y1: Int
    var x2: Int
    var y2: Int
    var thickness: Int
}

@available(macOS 27.0, *)
@Generable
struct WallExtraction: Codable {
    @Guide(description: "At most 256 physical wall centerline segments")
    var segments: [WallSegment]
}

@main
struct FoundationModelsWallSpike {
    static func main() async throws {
        guard #available(macOS 27.0, *) else {
            throw SpikeError.unsupportedOS
        }
        guard CommandLine.arguments.count == 3 else {
            throw SpikeError.usage
        }

        let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let session = LanguageModelSession(instructions: """
            You extract navigation-blocking walls from 2D floor plans. Ignore text,
            dimensions, furniture, fixtures, floor patterns, shadows, and paper edges.
            Coordinates range from 0 to 1000 with the origin at the image top-left.
            Split walls at doors and passable openings so those openings remain free.
            """)
        let response = try await session.respond(generating: WallExtraction.self) {
            "Extract physical walls as straight centerline segments. Use no more than 256 segments."
            Attachment(imageURL: imageURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(response.content).write(to: outputURL, options: .atomic)
    }

    enum SpikeError: LocalizedError {
        case unsupportedOS
        case usage

        var errorDescription: String? {
            switch self {
            case .unsupportedOS:
                return "Image prompting requires macOS 27 or iOS 27."
            case .usage:
                return "Usage: foundation_models_wall_spike <image> <output.json>"
            }
        }
    }
}

