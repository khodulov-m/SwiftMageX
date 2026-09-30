import MCP
import SwiftMageXKit

/// `edit_image` — mirrors `swiftmagex edit`. Image-to-image / inpainting via
/// Gemini's `:generateContent` endpoint; the source image (and optional mask)
/// are sent as inline parts alongside the text prompt.
enum EditImageTool {
    /// MCP tool name.
    static let name = "edit_image"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let image: String
        let references: [String]
        let prompt: String
        let mask: String?
        let aspectRatio: AspectRatio?
        let resolution: ImageResolution?
        let count: Int
        let seed: UInt64?
        let model: String
        let output: String?
    }

    /// Default model identifier when the caller does not pass `model`.
    static let defaultModel = ModelCatalog.defaultModelID

    /// Parses arguments, throwing ``MCPError/invalidParams(_:)`` on schema
    /// failures (missing keys, wrong types, out-of-range values).
    static func parse(_ raw: [String: Value]?) throws -> Input {
        let args = ToolArguments(raw, toolName: name)
        let image = try args.requiredString("image")
        let references = try args.optionalStringArray("references") ?? []
        let prompt = try args.requiredString("prompt")
        let mask = try args.optionalString("mask")
        let aspectRatio = try args.optionalAspectRatio("aspect_ratio")
        let resolution = try args.optionalResolution("resolution")
        let count = try args.optionalInt("count") ?? 1
        guard (1...4).contains(count) else {
            throw MCPError.invalidParams("\(name): 'count' must be between 1 and 4 (got \(count))")
        }
        let seed = try args.optionalUInt64("seed")
        let model = try args.optionalString("model") ?? defaultModel
        let output = try args.optionalString("output")
        return Input(
            image: image,
            references: references,
            prompt: prompt,
            mask: mask,
            aspectRatio: aspectRatio,
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
        description: "Edit an image with a Gemini model (image-to-image / multi-image edit / inpainting). The source image is sent inline alongside the prompt; an optional list of additional reference images lets the prompt compose across them; an optional mask marks the region to edit on the primary image. Returns absolute paths and the edited image content.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "image": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the primary source image (PNG or JPEG)."),
                ]),
                "references": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                    ]),
                    "description": .string("Optional additional reference images (PNG or JPEG). Each path becomes an extra inline image part the prompt can compose against — e.g. \"take the subject from image 1 and place it in scene 2\"."),
                ]),
                "prompt": .object([
                    "type": .string("string"),
                    "description": .string("Text instruction describing the edit."),
                ]),
                "mask": .object([
                    "type": .string("string"),
                    "description": .string("Optional path to a grayscale/binary mask (PNG or JPEG). White marks the region to edit, black preserves the original. Applied against the primary image."),
                ]),
                "aspect_ratio": .object([
                    "type": .string("string"),
                    "enum": .array(AspectRatio.allCases.map { .string($0.rawValue) }),
                    "description": .string("Output aspect ratio (width:height). Defaults to the primary image's proportions. Per model — 3.1 Flash: all ratios, 512–4K; 3.1 Flash Lite: all ratios, 512 and 1K only; 3 Pro: no 1:4/4:1/1:8/8:1, 1K–4K."),
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
                    "description": .string("Gemini model identifier. Defaults to \(defaultModel); all listed models are GA."),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Destination file or directory. Absolute paths recommended."),
                ]),
            ]),
            "required": .array([.string("image"), .string("prompt")]),
        ])
    )
}
