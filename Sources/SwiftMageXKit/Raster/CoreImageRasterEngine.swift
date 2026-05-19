import CoreGraphics
import Foundation
import ImageIO

/// CoreImage / CoreText / ImageIO implementation of ``RasterEngine``.
///
/// The only ``RasterEngine`` implementation in MVP 0.1 (spec §9). All methods
/// are stubs for now; real implementations land in milestone 2 (`resize`),
/// milestone 3 (`text`), and milestone 5 (metadata-aware `write`).
public struct CoreImageRasterEngine: RasterEngine {
    /// Creates a CoreImage-backed raster engine.
    public init() {}

    public func load(from url: URL) throws -> RasterImage {
        // TODO(milestone 2): decode via ImageIO (CGImageSourceCreateWithURL).
        _ = url
        throw SwiftMageXError.raster("CoreImageRasterEngine.load is not implemented yet (milestone 2)")
    }

    public func resize(_ image: RasterImage, to spec: ResizeSpec) throws -> RasterImage {
        // TODO(milestone 2): CoreImage Lanczos resize with contain/cover/fill modes.
        _ = image
        _ = spec
        throw SwiftMageXError.raster("CoreImageRasterEngine.resize is not implemented yet (milestone 2)")
    }

    public func overlayText(_ image: RasterImage, _ spec: TextSpec) throws -> RasterImage {
        // TODO(milestone 3): CoreText layout with wrapping, stroke, and safe-zone positioning.
        _ = image
        _ = spec
        throw SwiftMageXError.raster("CoreImageRasterEngine.overlayText is not implemented yet (milestone 3)")
    }

    public func write(
        _ image: RasterImage,
        to url: URL,
        format: ImageFormat,
        quality: Double,
        metadata: ImageMetadata?
    ) throws {
        // TODO(milestone 2/5): ImageIO destination with PNG tEXt / JPEG EXIF metadata.
        _ = image
        _ = url
        _ = format
        _ = quality
        _ = metadata
        throw SwiftMageXError.raster("CoreImageRasterEngine.write is not implemented yet (milestone 2)")
    }
}
