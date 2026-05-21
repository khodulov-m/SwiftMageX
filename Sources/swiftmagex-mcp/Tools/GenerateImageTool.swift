import MCP
import SwiftMageXKit

/// `generate_image` — mirrors `swiftmagex generate` (spec §6.1, §7).
enum GenerateImageTool {
    /// MCP tool name.
    static let name = "generate_image"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let prompt: String
        let size: ImageSize
        let count: Int
        let seed: UInt64?
        let model: String
        let output: String?
    }

    /// Default model identifier when the caller does not pass `model`.
    /// Kept in sync with `GenerateCommand`'s default (spec §8).
    static let defaultModel = ModelCatalog.defaultModelID

    /// Parses arguments, throwing ``MCPError/invalidParams(_:)`` on schema
    /// failures (missing keys, wrong types, out-of-range values).
    static func parse(_ raw: [String: Value]?) throws -> Input {
        let args = ToolArguments(raw, toolName: name)
        let prompt = try args.requiredString("prompt")
        let size = try args.optionalEnum("size", as: ImageSize.self) ?? .square
        let count = try args.optionalInt("count") ?? 1
        guard (1...4).contains(count) else {
            throw MCPError.invalidParams("\(name): 'count' must be between 1 and 4 (got \(count))")
        }
        let seed = try args.optionalUInt64("seed")
        let model = try args.optionalString("model") ?? defaultModel
        let output = try args.optionalString("output")
        return Input(
            prompt: prompt,
            size: size,
            count: count,
            seed: seed,
            model: model,
            output: output
        )
    }

    /// MCP tool descriptor with full input schema.
    static let descriptor = Tool(
        name: name,
        description: "Generate an image from a text prompt using a Google AI image model (Gemini or Imagen). Returns absolute paths and the image content.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "prompt": .object([
                    "type": .string("string"),
                    "description": .string("Text prompt describing the image to generate."),
                ]),
                "size": .object([
                    "type": .string("string"),
                    "enum": .array([.string("square"), .string("portrait"), .string("landscape")]),
                    "description": .string("Aspect ratio of the generated image. Defaults to square."),
                ]),
                "count": .object([
                    "type": .string("integer"),
                    "minimum": .int(1),
                    "maximum": .int(4),
                    "description": .string("Number of variants to generate (1–4). Defaults to 1."),
                ]),
                "seed": .object([
                    "type": .string("integer"),
                    "minimum": .int(0),
                    "description": .string("Seed for reproducibility. Support is provider-dependent."),
                ]),
                "model": .object([
                    "type": .string("string"),
                    "enum": .array(ModelCatalog.all.map { .string($0.id) }),
                    "description": .string("Image model identifier. Defaults to \(defaultModel). Gemini (`gemini-*`) and Imagen (`imagen-*`) families are routed automatically."),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Destination file or directory. Absolute paths recommended."),
                ]),
            ]),
            "required": .array([.string("prompt")]),
        ])
    )
}
