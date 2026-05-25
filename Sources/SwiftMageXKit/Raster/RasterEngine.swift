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

    /// Alpha-composite `foreground` onto `background` according to `spec`.
    ///
    /// The result has `background`'s dimensions; `foreground` is scaled,
    /// anchored, and blended on top.
    func composite(
        _ foreground: RasterImage,
        onto background: RasterImage,
        _ spec: CompositeSpec
    ) throws -> RasterImage

    /// Place `screenshot` into the screen cutout of a device `frame`.
    ///
    /// `frame` is a bezel image with a transparent screen hole; the screenshot
    /// is scaled into that hole and the bezel drawn on top. The result keeps
    /// `frame`'s dimensions and its surrounding transparency, ready to be
    /// composited onto a background.
    func frameScreenshot(
        _ screenshot: RasterImage,
        in frame: RasterImage,
        _ spec: DeviceFrameSpec
    ) throws -> RasterImage

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

/// Parameters for ``RasterEngine/composite(_:onto:_:)``.
public struct CompositeSpec: Sendable, Equatable {
    /// Anchor of the foreground within the background. Reuses the text
    /// overlay's seven-position scheme.
    public var position: TextPosition
    /// The foreground is contain-fit into a box of `scale × background size`,
    /// preserving aspect ratio. `1.0` fits it inside the full background.
    public var scale: Double
    /// Horizontal nudge from the anchored position, in pixels (positive = right).
    public var offsetX: Int
    /// Vertical nudge from the anchored position, in pixels (positive = down).
    public var offsetY: Int
    /// Blend opacity of the foreground, `0.0`–`1.0`.
    public var opacity: Double

    /// Creates a composite specification.
    public init(
        position: TextPosition = .center,
        scale: Double = 1.0,
        offsetX: Int = 0,
        offsetY: Int = 0,
        opacity: Double = 1.0
    ) {
        self.position = position
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.opacity = opacity
    }
}

/// Parameters for ``RasterEngine/frameScreenshot(_:in:_:)``.
public struct DeviceFrameSpec: Sendable, Equatable {
    /// The screen cutout in frame-pixel coordinates, origin at the top-left.
    public struct ScreenRect: Sendable, Equatable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int

        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Where the screenshot goes inside the frame. `nil` auto-detects the
    /// enclosed transparent region from the frame's alpha channel.
    public var screenRect: ScreenRect?
    /// Alpha value (0–255) below which a pixel counts as transparent during
    /// auto-detection.
    public var alphaThreshold: Int
    /// How the screenshot fills the screen rect. `.cover` (the default) fills
    /// it completely, cropping overflow.
    public var screenFit: ResizeFit

    /// Creates a device-frame specification.
    public init(
        screenRect: ScreenRect? = nil,
        alphaThreshold: Int = 16,
        screenFit: ResizeFit = .cover
    ) {
        self.screenRect = screenRect
        self.alphaThreshold = alphaThreshold
        self.screenFit = screenFit
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
