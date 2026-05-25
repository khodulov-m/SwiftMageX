import MCP
import SwiftMageXKit

/// `composite_images` — mirrors `swiftmagex composite`.
enum CompositeImagesTool {
    /// MCP tool name.
    static let name = "composite_images"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let input: String
        let overlay: String
        let position: TextPosition
        let scale: Double
        let offsetX: Int
        let offsetY: Int
        let opacity: Double
        let output: String?
        let format: ImageFormat?
        let quality: Double
    }

    /// Parses arguments, throwing ``MCPError/invalidParams(_:)`` on schema
    /// failures. Cross-field validation mirrors `CompositeCommand.validate()`.
    static func parse(_ raw: [String: Value]?) throws -> Input {
        let args = ToolArguments(raw, toolName: name)
        let input = try args.requiredString("input")
        let overlay = try args.requiredString("overlay")
        let position = try parsePosition(args) ?? .center
        let scale = try args.optionalDouble("scale") ?? 1.0
        let offsetX = try args.optionalInt("offset_x") ?? 0
        let offsetY = try args.optionalInt("offset_y") ?? 0
        let opacity = try args.optionalDouble("opacity") ?? 1.0
        let output = try args.optionalString("output")
        let format = try parseFormat(args)
        let quality = try args.optionalDouble("quality") ?? 0.9

        guard scale > 0 else {
            throw MCPError.invalidParams("\(name): 'scale' must be positive (got \(scale))")
        }
        guard (0.0...1.0).contains(opacity) else {
            throw MCPError.invalidParams("\(name): 'opacity' must be 0.0–1.0 (got \(opacity))")
        }
        guard (0.0...1.0).contains(quality) else {
            throw MCPError.invalidParams("\(name): 'quality' must be 0.0–1.0 (got \(quality))")
        }

        return Input(
            input: input,
            overlay: overlay,
            position: position,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY,
            opacity: opacity,
            output: output,
            format: format,
            quality: quality
        )
    }

    private static func parsePosition(_ args: ToolArguments) throws -> TextPosition? {
        guard let raw = try args.optionalString("position") else { return nil }
        let normalized = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        guard let position = TextPosition(rawValue: normalized) else {
            throw MCPError.invalidParams("\(name): 'position' has unrecognized value '\(raw)'")
        }
        return position
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
        description: "Composite one image onto another locally — no AI. Returns the absolute output path.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "input": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the background (canvas) image."),
                ]),
                "overlay": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the foreground image pasted on top."),
                ]),
                "position": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("top"), .string("center"), .string("bottom"),
                        .string("top-left"), .string("top-right"),
                        .string("bottom-left"), .string("bottom-right"),
                    ]),
                    "description": .string("Anchor position of the foreground. Defaults to center."),
                ]),
                "scale": .object([
                    "type": .string("number"),
                    "minimum": .double(0.0),
                    "description": .string("Foreground size as a fraction of the background. Defaults to 1.0."),
                ]),
                "offset_x": .object([
                    "type": .string("integer"),
                    "description": .string("Horizontal nudge in pixels (positive = right). Defaults to 0."),
                ]),
                "offset_y": .object([
                    "type": .string("integer"),
                    "description": .string("Vertical nudge in pixels (positive = down). Defaults to 0."),
                ]),
                "opacity": .object([
                    "type": .string("number"),
                    "minimum": .double(0.0),
                    "maximum": .double(1.0),
                    "description": .string("Foreground opacity, 0.0–1.0. Defaults to 1.0."),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Absolute destination path. Defaults to a sibling of the background."),
                ]),
                "format": .object([
                    "type": .string("string"),
                    "enum": .array([.string("png"), .string("jpeg")]),
                    "description": .string("Output format. Defaults to the background format."),
                ]),
                "quality": .object([
                    "type": .string("number"),
                    "minimum": .double(0.0),
                    "maximum": .double(1.0),
                    "description": .string("JPEG quality, 0.0–1.0. Defaults to 0.9."),
                ]),
            ]),
            "required": .array([.string("input"), .string("overlay")]),
        ])
    )
}
