import MCP
import SwiftMageXKit

/// `compose_icon` — mirrors `swiftmagex icon`.
///
/// Assembles an Icon Composer `.icon` package (Liquid Glass app icons for
/// iOS 26+/macOS 26+) from prepared layer images. Local-only — no AI
/// provider, no API key. Layer preparation belongs to the other tools
/// (`generate_image`, `remove_background`, `resize_image`).
enum ComposeIconTool {
    /// MCP tool name.
    static let name = "compose_icon"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let layers: [IconLayerSpec]
        let fill: IconFill
        let output: String?
        let overwrite: Bool
        let flatPreview: Bool
        let flatPreviewOutput: String?
        let validate: Bool
    }

    /// Parses arguments, throwing ``MCPError/invalidParams(_:)`` on schema
    /// failures. Fill and layer-option validation happens here so malformed
    /// input never reaches the kit as a half-built spec.
    static func parse(_ raw: [String: Value]?) throws -> Input {
        let args = ToolArguments(raw, toolName: name)

        guard let rawLayers = try args.optionalObjectArray("layers"), !rawLayers.isEmpty else {
            throw MCPError.invalidParams(
                "\(name): 'layers' must be a non-empty array of layer objects"
            )
        }
        let layers = try rawLayers.map(parseLayer)

        let fill: IconFill
        if let rawFill = try args.optionalString("fill") {
            fill = try mapInvalidInput { try IconFill.parse(rawFill) }
        } else {
            fill = .solid("#FFFFFF")
        }

        return Input(
            layers: layers,
            fill: fill,
            output: try args.optionalString("output"),
            overwrite: try args.optionalBool("overwrite") ?? false,
            flatPreview: try args.optionalBool("flat_preview") ?? false,
            flatPreviewOutput: try args.optionalString("flat_preview_output"),
            validate: try args.optionalBool("validate") ?? false
        )
    }

    private static func parseLayer(_ raw: [String: Value]) throws -> IconLayerSpec {
        let layer = ToolArguments(raw, toolName: name)
        let spec = IconLayerSpec(
            path: try layer.requiredString("path"),
            name: try layer.optionalString("name"),
            glass: try layer.optionalBool("glass"),
            scale: try layer.optionalDouble("scale"),
            dx: try layer.optionalDouble("dx"),
            dy: try layer.optionalDouble("dy"),
            fill: try layer.optionalString("fill"),
            group: try layer.optionalInt("group") ?? 1
        )
        if let hex = spec.fill {
            _ = try mapInvalidInput { try IconFill.parse("solid:\(hex)") }
        }
        return spec
    }

    /// Reruns kit-level parsing as schema validation: an
    /// ``SwiftMageXError/invalidInput(_:)`` thrown while decoding arguments
    /// is a malformed-parameter problem, not a runtime failure.
    private static func mapInvalidInput<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as SwiftMageXError {
            throw MCPError.invalidParams("\(name): \(error.message)")
        }
    }

    /// MCP tool descriptor with full input schema.
    static let descriptor = Tool(
        name: name,
        description: "Assemble an Apple Icon Composer .icon package (Liquid Glass app icon for iOS 26+/macOS 26+) from prepared layer images — no AI, no API key. Prepare the layers first with generate_image / remove_background / resize_image; this tool stacks them on the 1024-pt canvas, writes icon.json plus Assets/, and returns the absolute package path. Optionally writes a flat PNG preview and compile-checks the package with Xcode's actool.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "layers": .object([
                    "type": .string("array"),
                    "minItems": .int(1),
                    "description": .string("Layer images bottom-to-top. PNG with transparency recommended (use remove_background to cut subjects out)."),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Absolute path to a prepared layer image."),
                            ]),
                            "name": .object([
                                "type": .string("string"),
                                "description": .string("Layer display name. Defaults to the file name."),
                            ]),
                            "glass": .object([
                                "type": .string("boolean"),
                                "description": .string("Liquid Glass treatment for this layer. Defaults to true."),
                            ]),
                            "scale": .object([
                                "type": .string("number"),
                                "description": .string("Multiplier on the layer's natural size (1 source pixel = 1 point on the 1024-pt canvas). Defaults to 1."),
                            ]),
                            "dx": .object([
                                "type": .string("number"),
                                "description": .string("Horizontal offset in points from centered placement (positive = right)."),
                            ]),
                            "dy": .object([
                                "type": .string("number"),
                                "description": .string("Vertical offset in points from centered placement (positive = down)."),
                            ]),
                            "fill": .object([
                                "type": .string("string"),
                                "description": .string("Solid tint for the layer as #RRGGBB or #RRGGBBAA."),
                            ]),
                            "group": .object([
                                "type": .string("integer"),
                                "minimum": .int(1),
                                "description": .string("1-based group index; layers of one group must be contiguous, max 4 per group. Defaults to 1."),
                            ]),
                        ]),
                        "required": .array([.string("path")]),
                    ]),
                ]),
                "fill": .object([
                    "type": .string("string"),
                    "description": .string("Icon background: 'solid:#RRGGBB[AA]' or 'auto:#RRGGBB[AA]' (system gradient seeded from the color). Defaults to solid:#FFFFFF."),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Destination .icon path ('.icon' appended when missing). Defaults to AppIcon.icon in the server's working directory."),
                ]),
                "overwrite": .object([
                    "type": .string("boolean"),
                    "description": .string("Replace an existing package atomically. Defaults to false."),
                ]),
                "flat_preview": .object([
                    "type": .string("boolean"),
                    "description": .string("Also write a flat 1024x1024 PNG composite (no Liquid Glass, no squircle mask) next to the package, returned as image content. Defaults to false."),
                ]),
                "flat_preview_output": .object([
                    "type": .string("string"),
                    "description": .string("Path for the flat preview PNG. Defaults to '<name>-flat.png' beside the package."),
                ]),
                "validate": .object([
                    "type": .string("boolean"),
                    "description": .string("Compile-check the package with Xcode's actool (requires Xcode 26). Defaults to false."),
                ]),
            ]),
            "required": .array([.string("layers")]),
        ])
    )
}
