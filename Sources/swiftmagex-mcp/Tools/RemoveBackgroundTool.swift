import MCP
import SwiftMageXKit

/// `remove_background` — mirrors `swiftmagex remove-bg` (spec §7).
///
/// Local Vision segmentation; no AI provider, no API key. The cutout always
/// carries alpha, so the result is written as PNG regardless of the source.
enum RemoveBackgroundTool {
    /// MCP tool name.
    static let name = "remove_background"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let input: String
        let output: String?
    }

    /// Parses arguments, throwing ``MCPError/invalidParams(_:)`` on schema
    /// failures.
    static func parse(_ raw: [String: Value]?) throws -> Input {
        let args = ToolArguments(raw, toolName: name)
        let input = try args.requiredString("input")
        let output = try args.optionalString("output")
        return Input(input: input, output: output)
    }

    /// MCP tool descriptor with full input schema.
    static let descriptor = Tool(
        name: name,
        description: "Remove an image's background locally with Vision, leaving the foreground subject on transparency — no AI, no API key. Always writes PNG (alpha). Returns the absolute output path.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "input": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the source image."),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Absolute destination path (written as PNG). Defaults to a sibling of the source."),
                ]),
            ]),
            "required": .array([.string("input")]),
        ])
    )
}
