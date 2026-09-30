import MCP
import SwiftMageXKit

/// `generate_image` — mirrors `swiftmagex generate` (spec §6.1, §7).
enum GenerateImageTool {
    /// MCP tool name.
    static let name = "generate_image"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let prompt: String
        let aspectRatio: AspectRatio?
        let resolution: ImageResolution?
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
        let size = try args.optionalEnum("size", as: ImageSize.self)
        let aspectRatio = try args.optionalAspectRatio("aspect_ratio")
        guard size == nil || aspectRatio == nil else {
            throw MCPError.invalidParams("\(name): 'size' and 'aspect_ratio' are mutually exclusive; pass one")
        }
        let resolution = try args.optionalResolution("resolution")
        let count = try args.optionalInt("count") ?? 1
        guard (1...4).contains(count) else {
            throw MCPError.invalidParams("\(name): 'count' must be between 1 and 4 (got \(count))")
        }
        let seed = try args.optionalUInt64("seed")
        let model = try args.optionalString("model") ?? defaultModel
        let output = try args.optionalString("output")
        return Input(
            prompt: prompt,
            aspectRatio: aspectRatio ?? size?.aspectRatio,
            resolution: resolution,
            count: count,
            seed: seed,
            model: model,
            output: output
        )
    }

    /// MCP tool descriptor with full input schema.
    static let descriptor = Tool(
        name: name,
        description: "Generate an image from a text prompt using a Gemini image model. Returns absolute paths and the image content.",
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
                    "description": .string("Aspect-ratio preset: square (1:1), portrait (9:16), landscape (16:9). Mutually exclusive with aspect_ratio. With neither, the model picks its own framing."),
                ]),
                "aspect_ratio": .object([
                    "type": .string("string"),
                    "enum": .array(AspectRatio.allCases.map { .string($0.rawValue) }),
                    "description": .string("Exact output aspect ratio (width:height). Mutually exclusive with size. Per model — 3.1 Flash: all ratios, 512–4K; 3.1 Flash Lite: all ratios, 512 and 1K only; 3 Pro: no 1:4/4:1/1:8/8:1, 1K–4K."),
                ]),
                "resolution": .object([
                    "type": .string("string"),
                    "enum": .array(ImageResolution.allCases.map { .string($0.rawValue) }),
                    "description": .string("Output resolution tier; 1K at 1:1 is 1024×1024, 2K doubles it, 4K quadruples it. Defaults to the model's own (1K)."),
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
                    // `enum` above closes the set, so unlike the CLI an MCP caller
                    // cannot reach a model the catalog does not list.
                    "description": .string("Image model identifier. Defaults to \(defaultModel); all listed models are GA."),
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
