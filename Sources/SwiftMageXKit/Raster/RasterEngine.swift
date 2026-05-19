import CoreGraphics
import Foundation

/// A local pixel engine — no AI, no network.
///
/// One implementation in MVP 0.1: ``CoreImageRasterEngine``. The protocol
/// exists for testability of command-layer logic; see spec §9.
public protocol RasterEngine: Sendable {
    /// Read an image from disk into an in-memory ``RasterImage``.
    func load(from url: URL) throws -> RasterImage

    /// Resize (and optionally crop or stretch) an image according to `spec`.
    func resize(_ image: RasterImage, to spec: ResizeSpec) throws -> RasterImage

    /// Compose a text overlay onto `image` according to `spec`.
    func overlayText(_ image: RasterImage, _ spec: TextSpec) throws -> RasterImage

    /// Write `image` to `url` in the chosen `format`, embedding optional `metadata`.
    func write(
        _ image: RasterImage,
        to url: URL,
        format: ImageFormat,
        quality: Double,
        metadata: ImageMetadata?
    ) throws
}

/// In-memory image handle passed between ``RasterEngine`` methods.
///
/// Wraps a `CGImage` so all back-ends share a single bitmap representation.
public struct RasterImage: @unchecked Sendable {
    /// The underlying Core Graphics bitmap. Treat as immutable.
    public let cgImage: CGImage

    /// Pixel width.
    public var width: Int { cgImage.width }
    /// Pixel height.
    public var height: Int { cgImage.height }

    /// Wraps a `CGImage`.
    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

/// How a target size should be applied to a source image.
public enum ResizeFit: String, Sendable, CaseIterable, Codable {
    /// Scale to fit fully inside the target box, preserving aspect ratio.
    case contain
    /// Scale to fill the target box, cropping overflow, preserving aspect ratio.
    case cover
    /// Stretch to exactly fill the target box, ignoring aspect ratio.
    case fill
}

/// Parameters for ``RasterEngine/resize(_:to:)``.
public struct ResizeSpec: Sendable, Equatable {
    /// Target width in pixels. If nil, computed from `height` preserving aspect ratio.
    public var width: Int?
    /// Target height in pixels. If nil, computed from `width` preserving aspect ratio.
    public var height: Int?
    /// How to apply the target size.
    public var fit: ResizeFit

    /// Creates a resize specification.
    public init(width: Int?, height: Int?, fit: ResizeFit) {
        self.width = width
        self.height = height
        self.fit = fit
    }
}

/// Where a text overlay should be anchored.
public enum TextPosition: String, Sendable, CaseIterable, Codable {
    case top
    case center
    case bottom
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
}

/// Parameters for ``RasterEngine/overlayText(_:_:)``.
public struct TextSpec: Sendable, Equatable {
    /// Text to render. Wrapped to the available width inside a safe zone.
    public var text: String
    /// Anchor position.
    public var position: TextPosition
    /// Optional font family name; nil means the system font.
    public var fontName: String?
    /// Point size of the glyphs.
    public var fontSize: Int
    /// Fill color in `#RRGGBB` / `#RRGGBBAA` form.
    public var color: String
    /// Optional stroke color; nil means no stroke.
    public var strokeColor: String?
    /// Stroke width in points.
    public var strokeWidth: Double

    /// Creates a text-overlay specification.
    public init(
        text: String,
        position: TextPosition,
        fontName: String?,
        fontSize: Int,
        color: String,
        strokeColor: String?,
        strokeWidth: Double
    ) {
        self.text = text
        self.position = position
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }
}

/// Metadata embedded into generated files (PNG `tEXt` / EXIF) via ImageIO.
///
/// Makes every generated output file self-documenting per spec §12.
public struct ImageMetadata: Sendable, Equatable {
    /// The prompt that produced the image, if any.
    public var prompt: String?
    /// The model identifier used to generate the image, if any.
    public var model: String?
    /// The seed used (or recorded intent if the provider does not support seeding).
    public var seed: UInt64?
    /// Wall-clock timestamp of generation.
    public var timestamp: Date
    /// SwiftMageX tool version that produced the file.
    public var toolVersion: String

    /// Creates an image-metadata record.
    public init(
        prompt: String?,
        model: String?,
        seed: UInt64?,
        timestamp: Date,
        toolVersion: String
    ) {
        self.prompt = prompt
        self.model = model
        self.seed = seed
        self.timestamp = timestamp
        self.toolVersion = toolVersion
    }
}
