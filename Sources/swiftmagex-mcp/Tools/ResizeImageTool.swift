import MCP
import SwiftMageXKit

/// `resize_image` — mirrors `swiftmagex resize` (spec §6.2, §7).
enum ResizeImageTool {
    /// MCP tool name.
    static let name = "resize_image"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let input: String
        let width: Int?
        let height: Int?
        let fit: ResizeFit
        let output: String?
        let format: ImageFormat?
        let quality: Double
    }

    /// Parses arguments, throwing ``MCPError/invalidParams(_:)`` on schema
    /// failures. Cross-field validation that mirrors `ResizeCommand.validate()`
    /// lives here so the MCP path can't bypass it.
    static func parse(_ raw: [String: Value]?) throws -> Input {
        let args = ToolArguments(raw, toolName: name)
        let input = try args.requiredString("input")
        let width = try args.optionalInt("width")
        let height = try args.optionalInt("height")
        let fit = try args.optionalEnum("fit", as: ResizeFit.self) ?? .contain
        let output = try args.optionalString("output")
        let format = try parseFormat(args)
        let quality = try args.optionalDouble("quality") ?? 0.9

        if width == nil && height == nil {
            throw MCPError.invalidParams("\(name): provide at least one of 'width' or 'height'")
        }
        if let w = width, w <= 0 {
            throw MCPError.invalidParams("\(name): 'width' must be positive (got \(w))")
        }
        if let h = height, h <= 0 {
            throw MCPError.invalidParams("\(name): 'height' must be positive (got \(h))")
        }
        guard (0.0...1.0).contains(quality) else {
            throw MCPError.invalidParams("\(name): 'quality' must be 0.0–1.0 (got \(quality))")
        }
        if fit == .cover || fit == .fill, width == nil || height == nil {
            throw MCPError.invalidParams("\(name): fit '\(fit.rawValue)' requires both 'width' and 'height'")
        }

        return Input(
            input: input,
            width: width,
            height: height,
            fit: fit,
            output: output,
            format: format,
            quality: quality
        )
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
        description: "Resize, crop, or convert an image locally — no AI, no API key. Returns the absolute output path.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "input": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the source image."),
                ]),
                "width": .object([
                    "type": .string("integer"),
                    "minimum": .int(1),
                    "description": .string("Target width in pixels."),
                ]),
                "height": .object([
                    "type": .string("integer"),
                    "minimum": .int(1),
                    "description": .string("Target height in pixels."),
                ]),
                "fit": .object([
                    "type": .string("string"),
                    "enum": .array([.string("contain"), .string("cover"), .string("fill")]),
                    "description": .string("Fit mode applied to the target size. Defaults to contain."),
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
            "required": .array([.string("input")]),
        ])
    )
}
