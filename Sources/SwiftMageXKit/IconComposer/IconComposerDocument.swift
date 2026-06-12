import Foundation

/// Codable model of an Icon Composer `icon.json` — the manifest at the root
/// of a `.icon` package (Liquid Glass app icons, iOS 26+ / macOS 26+).
///
/// The format is not publicly documented; this model mirrors packages
/// produced by Icon Composer itself. Every optional property is encoded
/// with `encodeIfPresent`, so the document only ever contains keys whose
/// meaning has been verified against real Icon Composer output — unknown
/// keys in foreign documents are tolerated on decode and dropped on
/// re-encode.
public struct IconComposerDocument: Codable, Sendable, Equatable {
    /// A background or layer-tint fill. Colors use Icon Composer's
    /// `srgb:R,G,B,A` string form (five decimal places, components 0–1).
    public enum Fill: Codable, Sendable, Equatable {
        /// Flat color.
        case solid(String)
        /// System-derived gradient seeded from one color.
        case automaticGradient(String)

        private enum CodingKeys: String, CodingKey {
            case solid
            case automaticGradient = "automatic-gradient"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try container.decodeIfPresent(String.self, forKey: .solid) {
                self = .solid(value)
            } else if let value = try container.decodeIfPresent(
                String.self, forKey: .automaticGradient
            ) {
                self = .automaticGradient(value)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "fill must contain 'solid' or 'automatic-gradient'"
                ))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .solid(let value):
                try container.encode(value, forKey: .solid)
            case .automaticGradient(let value):
                try container.encode(value, forKey: .automaticGradient)
            }
        }
    }

    /// Placement of a layer on the 1024-pt canvas.
    ///
    /// `translationInPoints` is the offset of the layer from its centered
    /// position, in points, y-down — *not* a top-left corner. `scale`
    /// multiplies the layer's natural size (1 source pixel = 1 point).
    /// Both derived from a real Icon Composer document where a 26 px badge
    /// at scale 15 / translation (222, 223) sits in the bottom-right corner.
    public struct Position: Codable, Sendable, Equatable {
        public var scale: Double
        public var translationInPoints: [Double]

        private enum CodingKeys: String, CodingKey {
            case scale
            case translationInPoints = "translation-in-points"
        }

        public init(scale: Double, translationInPoints: [Double]) {
            self.scale = scale
            self.translationInPoints = translationInPoints
        }
    }

    /// A per-appearance fill override for a layer. `appearance` is omitted
    /// for the default appearance; Icon Composer also writes "dark".
    public struct FillSpecialization: Codable, Sendable, Equatable {
        public var appearance: String?
        public var value: Fill

        public init(appearance: String? = nil, value: Fill) {
            self.appearance = appearance
            self.value = value
        }
    }

    /// One artwork layer, referencing an image inside the package's
    /// `Assets/` folder by file name.
    public struct Layer: Codable, Sendable, Equatable {
        public var imageName: String
        public var name: String
        /// Liquid Glass treatment. Icon Composer's default is `true`;
        /// omitted unless explicitly chosen.
        public var glass: Bool?
        public var hidden: Bool?
        public var position: Position?
        public var fillSpecializations: [FillSpecialization]?

        private enum CodingKeys: String, CodingKey {
            case imageName = "image-name"
            case name
            case glass
            case hidden
            case position
            case fillSpecializations = "fill-specializations"
        }

        public init(
            imageName: String,
            name: String,
            glass: Bool? = nil,
            hidden: Bool? = nil,
            position: Position? = nil,
            fillSpecializations: [FillSpecialization]? = nil
        ) {
            self.imageName = imageName
            self.name = name
            self.glass = glass
            self.hidden = hidden
            self.position = position
            self.fillSpecializations = fillSpecializations
        }
    }

    /// Group-level drop shadow.
    public struct Shadow: Codable, Sendable, Equatable {
        public var kind: String
        public var opacity: Double

        public init(kind: String = "neutral", opacity: Double = 0.5) {
            self.kind = kind
            self.opacity = opacity
        }
    }

    /// Group-level translucency.
    public struct Translucency: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var value: Double

        public init(enabled: Bool = true, value: Double = 0.5) {
            self.enabled = enabled
            self.value = value
        }
    }

    /// A stack of up to four layers sharing glass properties.
    public struct Group: Codable, Sendable, Equatable {
        public var layers: [Layer]
        public var shadow: Shadow?
        public var translucency: Translucency?

        public init(
            layers: [Layer],
            shadow: Shadow? = nil,
            translucency: Translucency? = nil
        ) {
            self.layers = layers
            self.shadow = shadow
            self.translucency = translucency
        }
    }

    public var fill: Fill?
    /// Front-to-back: the first group renders on top, matching the Icon
    /// Composer sidebar (verified against a real document where the badge
    /// group precedes the artwork it overlaps).
    public var groups: [Group]
    public var supportedPlatforms: [String: String]

    private enum CodingKeys: String, CodingKey {
        case fill
        case groups
        case supportedPlatforms = "supported-platforms"
    }

    public init(
        fill: Fill? = nil,
        groups: [Group],
        supportedPlatforms: [String: String] = ["squares": "shared"]
    ) {
        self.fill = fill
        self.groups = groups
        self.supportedPlatforms = supportedPlatforms
    }

    /// Encode to deterministic, pretty-printed JSON matching Icon Composer's
    /// own formatting conventions (sorted keys, unescaped slashes).
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
