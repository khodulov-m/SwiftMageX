import Foundation

/// One user-supplied layer for ``SwiftMageXOrchestrator/composeIcon(layers:fill:output:overwrite:flatPreview:flatPreviewOutput:validate:validator:engine:timestamp:currentDirectoryPath:)``.
///
/// Layers are listed bottom-to-top; `nil` options mean "Icon Composer
/// default" and are omitted from the emitted `icon.json`.
public struct IconLayerSpec: Sendable, Equatable {
    /// Source image path (PNG recommended; other formats are re-encoded).
    public var path: String
    /// Layer display name; defaults to the sanitized source-file stem.
    public var name: String?
    /// Liquid Glass treatment; Icon Composer defaults to `true`.
    public var glass: Bool?
    /// Multiplier on the layer's natural size (1 source pixel = 1 point on
    /// the 1024-pt canvas). Defaults to 1.
    public var scale: Double?
    /// Horizontal offset in points from centered placement (positive = right).
    public var dx: Double?
    /// Vertical offset in points from centered placement (positive = down).
    public var dy: Double?
    /// Solid tint as `#RRGGBB[AA]`, applied to all appearances.
    public var fill: String?
    /// 1-based group index; layers of one group must be contiguous.
    public var group: Int

    public init(
        path: String,
        name: String? = nil,
        glass: Bool? = nil,
        scale: Double? = nil,
        dx: Double? = nil,
        dy: Double? = nil,
        fill: String? = nil,
        group: Int = 1
    ) {
        self.path = path
        self.name = name
        self.glass = glass
        self.scale = scale
        self.dx = dx
        self.dy = dy
        self.fill = fill
        self.group = group
    }
}

/// The icon background, parsed from the user-facing `kind:#RRGGBB[AA]` form.
public enum IconFill: Sendable, Equatable {
    /// Flat color (hex payload).
    case solid(String)
    /// System gradient seeded from one color (hex payload).
    case automaticGradient(String)

    /// Parses `solid:#RRGGBB[AA]` or `auto:#RRGGBB[AA]`.
    ///
    /// - Throws: ``SwiftMageXError/invalidInput(_:)`` for an unknown kind or
    ///   a malformed color.
    public static func parse(_ raw: String) throws -> IconFill {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            throw SwiftMageXError.invalidInput(
                "malformed fill '\(raw)'; use solid:#RRGGBB or auto:#RRGGBB"
            )
        }
        let hex = String(parts[1])
        _ = try srgbString(fromHex: hex)
        switch parts[0].lowercased() {
        case "solid":
            return .solid(hex)
        case "auto", "auto-gradient", "automatic-gradient":
            return .automaticGradient(hex)
        default:
            throw SwiftMageXError.invalidInput(
                "unknown fill kind '\(parts[0])'; use solid:#RRGGBB or auto:#RRGGBB"
            )
        }
    }

    /// The hex payload, `#RRGGBB[AA]`.
    public var hex: String {
        switch self {
        case .solid(let hex), .automaticGradient(let hex):
            return hex
        }
    }

    /// The document-level fill with the color in `srgb:` form.
    func documentFill() throws -> IconComposerDocument.Fill {
        switch self {
        case .solid(let hex):
            return .solid(try Self.srgbString(fromHex: hex))
        case .automaticGradient(let hex):
            return .automaticGradient(try Self.srgbString(fromHex: hex))
        }
    }

    /// Converts `#RRGGBB[AA]` to Icon Composer's `srgb:R,G,B,A` string.
    ///
    /// - Throws: ``SwiftMageXError/invalidInput(_:)`` for malformed input.
    static func srgbString(fromHex hex: String) throws -> String {
        guard let color = CoreImageRasterEngine.parseHexColor(hex),
              let components = color.components,
              components.count == 4 else {
            throw SwiftMageXError.invalidInput(
                "malformed color '\(hex)'; use #RRGGBB or #RRGGBBAA"
            )
        }
        let formatted = components.map { String(format: "%.5f", Double($0)) }
        return "srgb:" + formatted.joined(separator: ",")
    }
}
