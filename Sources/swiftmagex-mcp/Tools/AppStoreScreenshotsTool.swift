import MCP
import SwiftMageXKit

/// `appstore_screenshots` — mirrors `swiftmagex appstore`.
enum AppStoreScreenshotsTool {
    /// MCP tool name.
    static let name = "appstore_screenshots"

    /// Typed inputs decoded from the MCP arguments dictionary.
    struct Input {
        let screenshot: String
        let background: String
        let frame: String?
        let frameSpec: DeviceFrameSpec
        let devices: [ASCDeviceSize]
        let orientation: Orientation
        let placement: CompositeSpec
        let caption: TextSpec?
        let output: String?
    }

    /// Parses arguments, throwing ``MCPError/invalidParams(_:)`` on schema
    /// failures. Cross-field validation mirrors `AppStoreCommand.validate()`.
    static func parse(_ raw: [String: Value]?) throws -> Input {
        let args = ToolArguments(raw, toolName: name)
        let screenshot = try args.requiredString("screenshot")
        let background = try args.requiredString("background")
        let frame = try args.optionalString("frame")
        let screenRect = try parseScreenRect(args)

        let deviceIDs = try args.optionalStringArray("devices") ?? []
        let devices: [ASCDeviceSize]
        do {
            devices = try ASCDeviceCatalog.sizes(for: deviceIDs)
        } catch let error as SwiftMageXError {
            throw MCPError.invalidParams("\(name): \(error.message)")
        }

        let orientation = try args.optionalEnum("orientation", as: Orientation.self) ?? .portrait

        let scale = try args.optionalDouble("scale") ?? 0.85
        guard scale > 0 else {
            throw MCPError.invalidParams("\(name): 'scale' must be positive (got \(scale))")
        }
        let position = try parsePosition(args, key: "position") ?? .center
        let placement = CompositeSpec(
            position: position,
            scale: scale,
            offsetX: try args.optionalInt("offset_x") ?? 0,
            offsetY: try args.optionalInt("offset_y") ?? 0,
            opacity: 1.0
        )

        let caption = try parseCaption(args)
        let output = try args.optionalString("output")

        return Input(
            screenshot: screenshot,
            background: background,
            frame: frame,
            frameSpec: DeviceFrameSpec(screenRect: screenRect),
            devices: devices,
            orientation: orientation,
            placement: placement,
            caption: caption,
            output: output
        )
    }

    private static func parseCaption(_ args: ToolArguments) throws -> TextSpec? {
        guard let text = try args.optionalString("caption") else { return nil }
        let fontSize = try args.optionalInt("font_size") ?? 96
        guard fontSize > 0 else {
            throw MCPError.invalidParams("\(name): 'font_size' must be positive (got \(fontSize))")
        }
        let strokeWidth = try args.optionalDouble("stroke_width") ?? 0.0
        guard strokeWidth >= 0 else {
            throw MCPError.invalidParams("\(name): 'stroke_width' must be non-negative (got \(strokeWidth))")
        }
        return TextSpec(
            text: text,
            position: try parsePosition(args, key: "caption_position") ?? .bottom,
            fontName: try args.optionalString("font"),
            fontSize: fontSize,
            color: try args.optionalString("color") ?? "#FFFFFF",
            strokeColor: try args.optionalString("stroke"),
            strokeWidth: strokeWidth
        )
    }

    private static func parsePosition(_ args: ToolArguments, key: String) throws -> TextPosition? {
        guard let raw = try args.optionalString(key) else { return nil }
        let normalized = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        guard let position = TextPosition(rawValue: normalized) else {
            throw MCPError.invalidParams("\(name): '\(key)' has unrecognized value '\(raw)'")
        }
        return position
    }

    private static func parseScreenRect(_ args: ToolArguments) throws -> DeviceFrameSpec.ScreenRect? {
        guard let raw = try args.optionalString("screen_rect") else { return nil }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let nums = parts.compactMap { Int($0) }
        guard parts.count == 4, nums.count == 4 else {
            throw MCPError.invalidParams("\(name): 'screen_rect' must be four integers x,y,width,height (got '\(raw)')")
        }
        guard nums[2] > 0, nums[3] > 0 else {
            throw MCPError.invalidParams("\(name): 'screen_rect' width and height must be positive (got '\(raw)')")
        }
        return DeviceFrameSpec.ScreenRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
    }

    /// MCP tool descriptor with full input schema.
    static let descriptor = Tool(
        name: name,
        description: "Prepare App Store Connect iPhone screenshots: frame a screenshot in a device bezel, scale it onto a background, overlay an optional caption, and emit one file per ASC device size. Returns absolute output paths.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "screenshot": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the screenshot placed into the device frame."),
                ]),
                "background": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the background image filled behind the device."),
                ]),
                "frame": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to a device bezel PNG with a transparent screen cutout. Omit to skip framing."),
                ]),
                "screen_rect": .object([
                    "type": .string("string"),
                    "description": .string("Screen cutout inside the frame as 'x,y,width,height' in pixels. Omit to auto-detect from the frame's alpha."),
                ]),
                "devices": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("ASC device size ids (\(ASCDeviceCatalog.all.map(\.id).joined(separator: ", ")), or 'all'). Defaults to \(ASCDeviceCatalog.defaultDeviceIDs.joined(separator: ", "))."),
                ]),
                "orientation": .object([
                    "type": .string("string"),
                    "enum": .array([.string("portrait"), .string("landscape")]),
                    "description": .string("Canvas orientation. Defaults to portrait."),
                ]),
                "scale": .object([
                    "type": .string("number"),
                    "minimum": .double(0.0),
                    "description": .string("Framed-device size as a fraction of the canvas. Defaults to 0.85."),
                ]),
                "position": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("top"), .string("center"), .string("bottom"),
                        .string("top-left"), .string("top-right"),
                        .string("bottom-left"), .string("bottom-right"),
                    ]),
                    "description": .string("Anchor of the framed device on the canvas. Defaults to center."),
                ]),
                "offset_x": .object([
                    "type": .string("integer"),
                    "description": .string("Horizontal nudge of the device in pixels. Defaults to 0."),
                ]),
                "offset_y": .object([
                    "type": .string("integer"),
                    "description": .string("Vertical nudge of the device in pixels. Defaults to 0."),
                ]),
                "caption": .object([
                    "type": .string("string"),
                    "description": .string("Caption text overlaid on the canvas. Omit for no caption."),
                ]),
                "caption_position": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("top"), .string("center"), .string("bottom"),
                        .string("top-left"), .string("top-right"),
                        .string("bottom-left"), .string("bottom-right"),
                    ]),
                    "description": .string("Anchor position of the caption. Defaults to bottom."),
                ]),
                "font": .object([
                    "type": .string("string"),
                    "description": .string("Caption font family name. Defaults to the system font."),
                ]),
                "font_size": .object([
                    "type": .string("integer"),
                    "minimum": .int(1),
                    "description": .string("Caption glyph point size. Defaults to 96."),
                ]),
                "color": .object([
                    "type": .string("string"),
                    "description": .string("Caption fill color in #RRGGBB or #RRGGBBAA form. Defaults to #FFFFFF."),
                ]),
                "stroke": .object([
                    "type": .string("string"),
                    "description": .string("Caption stroke color in #RRGGBB form. Omit for no stroke."),
                ]),
                "stroke_width": .object([
                    "type": .string("number"),
                    "minimum": .double(0.0),
                    "description": .string("Caption stroke width in points. Defaults to 0."),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Absolute output directory. Defaults to the server's working directory."),
                ]),
            ]),
            "required": .array([.string("screenshot"), .string("background")]),
        ])
    )
}
