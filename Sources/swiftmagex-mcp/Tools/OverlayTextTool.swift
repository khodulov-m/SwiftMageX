import MCP
import SwiftMageXKit

/// `overlay_text` — mirrors `swiftmagex text` (spec §6.3, §7).
enum OverlayTextTool {
    /// MCP tool name.
    static let name = "overlay_text"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let input: String
        let text: String
        let position: TextPosition
        let font: String?
        let fontSize: Int
        let color: String
        let stroke: String?
        let strokeWidth: Double
        let output: String?
    }

    /// Parses arguments, throwing ``MCPError/invalidParams(_:)`` on schema
    /// failures. Hex-color validation is deferred to the raster engine so the
    /// MCP path produces the same ``SwiftMageXError/invalidInput(_:)`` mapping
    /// as the CLI for malformed colors.
    static func parse(_ raw: [String: Value]?) throws -> Input {
        let args = ToolArguments(raw, toolName: name)
        let input = try args.requiredString("input")
        let text = try args.requiredString("text")
        let position = try parsePosition(args) ?? .bottom
        let font = try args.optionalString("font")
        let fontSize = try args.optionalInt("font_size") ?? 48
        let color = try args.optionalString("color") ?? "#FFFFFF"
        let stroke = try args.optionalString("stroke")
        let strokeWidth = try args.optionalDouble("stroke_width") ?? 2.0
        let output = try args.optionalString("output")

        guard fontSize > 0 else {
            throw MCPError.invalidParams("\(name): 'font_size' must be positive (got \(fontSize))")
        }
        guard strokeWidth >= 0 else {
            throw MCPError.invalidParams("\(name): 'stroke_width' must be non-negative (got \(strokeWidth))")
        }
        return Input(
            input: input,
            text: text,
            position: position,
            font: font,
            fontSize: fontSize,
            color: color,
            stroke: stroke,
            strokeWidth: strokeWidth,
            output: output
        )
    }

    /// Accepts both spec-canonical forms (`top-left`) and the underscore
    /// variant (`top_left`) some MCP clients prefer.
    private static func parsePosition(_ args: ToolArguments) throws -> TextPosition? {
        guard let raw = try args.optionalString("position") else { return nil }
        let normalized = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        guard let position = TextPosition(rawValue: normalized) else {
            throw MCPError.invalidParams("\(name): 'position' has unrecognized value '\(raw)'")
        }
        return position
    }

    /// MCP tool descriptor with full input schema.
    static let descriptor = Tool(
        name: name,
        description: "Overlay text onto an existing image — no AI. Returns the absolute output path.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "input": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the source image."),
                ]),
                "text": .object([
                    "type": .string("string"),
                    "description": .string("Text to overlay onto the image."),
                ]),
                "position": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("top"),
                        .string("center"),
                        .string("bottom"),
                        .string("top-left"),
                        .string("top-right"),
                        .string("bottom-left"),
                        .string("bottom-right"),
                    ]),
                    "description": .string("Anchor position of the overlay. Defaults to bottom."),
                ]),
                "font": .object([
                    "type": .string("string"),
                    "description": .string("Font family name. Defaults to the system font."),
                ]),
                "font_size": .object([
                    "type": .string("integer"),
                    "minimum": .int(1),
                    "description": .string("Glyph point size. Defaults to 48."),
                ]),
                "color": .object([
                    "type": .string("string"),
                    "description": .string("Fill color in #RRGGBB or #RRGGBBAA form. Defaults to #FFFFFF."),
                ]),
                "stroke": .object([
                    "type": .string("string"),
                    "description": .string("Stroke color in #RRGGBB form. Omit for no stroke."),
                ]),
                "stroke_width": .object([
                    "type": .string("number"),
                    "minimum": .double(0.0),
                    "description": .string("Stroke width in points. Defaults to 2.0."),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Absolute destination path. Defaults to a sibling of the source."),
                ]),
            ]),
            "required": .array([.string("input"), .string("text")]),
        ])
    )
}
