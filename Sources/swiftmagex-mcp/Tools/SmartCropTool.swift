import MCP
import SwiftMageXKit

/// `smart_crop` — mirrors `swiftmagex crop`.
///
/// Saliency-driven aspect-ratio crop using Vision's on-device attention model.
/// No AI provider, no API key. Output format defaults to the source format.
enum SmartCropTool {
    /// MCP tool name.
    static let name = "smart_crop"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let input: String
        let aspectWidth: Int
        let aspectHeight: Int
        let output: String?
        let format: ImageFormat?
        let quality: Double
    }

    /// Parses arguments, throwing ``MCPError/invalidParams(_:)`` on schema
    /// failures. Cross-field validation mirrors `CropCommand.validate()` so
    /// the MCP path can't bypass it.
    static func parse(_ raw: [String: Value]?) throws -> Input {
        let args = ToolArguments(raw, toolName: name)
        let input = try args.requiredString("input")
        let aspectRaw = try args.requiredString("aspect")
        let (aspectWidth, aspectHeight) = try parseAspect(aspectRaw)
        let output = try args.optionalString("output")
        let format = try parseFormat(args)
        let quality = try args.optionalDouble("quality") ?? 0.9

        guard (0.0...1.0).contains(quality) else {
            throw MCPError.invalidParams("\(name): 'quality' must be 0.0–1.0 (got \(quality))")
        }

        return Input(
            input: input,
            aspectWidth: aspectWidth,
            aspectHeight: aspectHeight,
            output: output,
            format: format,
            quality: quality
        )
    }

    private static func parseAspect(_ raw: String) throws -> (Int, Int) {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let w = Int(parts[0]), let h = Int(parts[1]),
              w > 0, h > 0 else {
            throw MCPError.invalidParams(
                "\(name): 'aspect' must be of the form W:H with positive integers (got '\(raw)')"
            )
        }
        return (w, h)
    }

    private static func parseFormat(_ args: ToolArguments) throws -> ImageFormat? {
        guard let raw = try args.optionalString("format") else { return nil }
        switch raw.lowercased() {
        case "png": return .png
        case "jpeg", "jpg": return .jpeg
        default:
            throw MCPError.invalidParams("\(name): 'format' must be one of png|jpeg (got '\(raw)')")
        }
    }

    /// MCP tool descriptor with full input schema.
    static let descriptor = Tool(
        name: name,
        description: "Smart-crop an image to an aspect ratio using Vision attention saliency — no AI, no API key. The crop window is centered on the salient region rather than the geometric center. Returns the absolute output path.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "input": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the source image."),
                ]),
                "aspect": .object([
                    "type": .string("string"),
                    "description": .string("Target aspect ratio in W:H form, e.g. '1:1', '4:5', '9:16'."),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Absolute destination path. Defaults to a sibling of the source."),
                ]),
                "format": .object([
                    "type": .string("string"),
                    "enum": .array([.string("png"), .string("jpeg")]),
                    "description": .string("Output format. Defaults to the source format."),
                ]),
                "quality": .object([
                    "type": .string("number"),
                    "minimum": .double(0.0),
                    "maximum": .double(1.0),
                    "description": .string("JPEG quality, 0.0–1.0. Defaults to 0.9."),
                ]),
            ]),
            "required": .array([.string("input"), .string("aspect")]),
        ])
    )
}
