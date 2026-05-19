import MCP

/// `overlay_text` — mirrors `swiftmagex text` (spec §6.3, §7).
enum OverlayTextTool {
    /// MCP tool name.
    static let name = "overlay_text"

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
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Absolute destination path. Defaults to a sibling of the source."),
                ]),
            ]),
            "required": .array([.string("input"), .string("text")]),
        ])
    )
}
