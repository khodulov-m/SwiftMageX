import MCP

/// `generate_image` — mirrors `swiftmagex generate` (spec §6.1, §7).
enum GenerateImageTool {
    /// MCP tool name.
    static let name = "generate_image"

    /// MCP tool descriptor with full input schema.
    static let descriptor = Tool(
        name: name,
        description: "Generate an image from a text prompt using the Gemini API. Returns absolute paths and the image content.",
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
                    "description": .string("Gemini model identifier. Defaults to gemini-2.5-flash-image."),
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
