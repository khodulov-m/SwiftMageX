import MCP

/// `resize_image` — mirrors `swiftmagex resize` (spec §6.2, §7).
enum ResizeImageTool {
    /// MCP tool name.
    static let name = "resize_image"

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
