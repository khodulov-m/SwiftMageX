import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// CoreImage / CoreText / ImageIO implementation of ``RasterEngine``.
///
/// The only ``RasterEngine`` implementation in MVP 0.1 (spec §9).
///
/// ImageIO reads PNG, JPEG, HEIC, and WebP natively on macOS 14+; writing in
/// 0.1 is limited to PNG and JPEG (see ``ImageFormat``).
public struct CoreImageRasterEngine: RasterEngine {
    /// Creates a CoreImage-backed raster engine.
    public init() {}

    // MARK: - Load

    public func load(from url: URL) throws -> RasterImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw SwiftMageXError.io("unable to open image: \(url.path)")
        }
        guard CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            let uti = CGImageSourceGetType(source).map { $0 as String } ?? "unknown"
            throw SwiftMageXError.raster("unsupported format: \(uti)")
        }
        return RasterImage(cgImage: cgImage)
    }

    // MARK: - Resize

    public func resize(_ image: RasterImage, to spec: ResizeSpec) throws -> RasterImage {
        let target = try resolveTargetSize(for: image, spec: spec)
        let source = image.cgImage
        let sourceW = source.width
        let sourceH = source.height

        switch spec.fit {
        case .contain, .fill:
            // Both fits scale the entire source into target dimensions; the
            // difference is only in how `target` was computed above.
            return try renderScaled(
                source,
                toWidth: target.width,
                toHeight: target.height
            )

        case .cover:
            // Scale so the source fully covers the target, then center-crop.
            let scale = max(
                Double(target.width) / Double(sourceW),
                Double(target.height) / Double(sourceH)
            )
            let scaledW = Int((Double(sourceW) * scale).rounded())
            let scaledH = Int((Double(sourceH) * scale).rounded())
            let scaled = try renderScaled(source, toWidth: scaledW, toHeight: scaledH)

            let cropX = max(0, (scaled.width - target.width) / 2)
            let cropY = max(0, (scaled.height - target.height) / 2)
            let rect = CGRect(
                x: cropX,
                y: cropY,
                width: min(target.width, scaled.width),
                height: min(target.height, scaled.height)
            )
            guard let cropped = scaled.cgImage.cropping(to: rect) else {
                throw SwiftMageXError.raster("cover crop failed")
            }
            return RasterImage(cgImage: cropped)
        }
    }

    // MARK: - Overlay text (milestone 3)

    public func overlayText(_ image: RasterImage, _ spec: TextSpec) throws -> RasterImage {
        _ = image
        _ = spec
        throw SwiftMageXError.raster("CoreImageRasterEngine.overlayText is not implemented yet (milestone 3)")
    }

    // MARK: - Write

    public func write(
        _ image: RasterImage,
        to url: URL,
        format: ImageFormat,
        quality: Double,
        metadata: ImageMetadata?
    ) throws {
        // Ensure the parent directory exists.
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            do {
                try FileManager.default.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true
                )
            } catch {
                throw SwiftMageXError.io("cannot create directory \(parent.path): \(error.localizedDescription)")
            }
        }

        let contentType: CFString
        switch format {
        case .png: contentType = UTType.png.identifier as CFString
        case .jpeg: contentType = UTType.jpeg.identifier as CFString
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            contentType,
            1,
            nil
        ) else {
            throw SwiftMageXError.io("cannot create image destination at \(url.path)")
        }

        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        // Metadata embedding lands in milestone 5; the parameter is accepted
        // today so the surface is stable.
        if let metadata = metadata {
            mergeMetadata(metadata, into: &properties, format: format)
        }

        CGImageDestinationAddImage(destination, image.cgImage, properties as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw SwiftMageXError.io("failed to write \(url.path)")
        }
    }

    // MARK: - Helpers

    private func resolveTargetSize(
        for image: RasterImage,
        spec: ResizeSpec
    ) throws -> (width: Int, height: Int) {
        let sourceW = image.width
        let sourceH = image.height
        guard sourceW > 0, sourceH > 0 else {
            throw SwiftMageXError.raster("source image has zero dimensions")
        }

        switch (spec.width, spec.height) {
        case (nil, nil):
            throw SwiftMageXError.invalidInput("at least one of width/height must be supplied")

        case (let w?, nil):
            let h = max(1, Int((Double(sourceH) * Double(w) / Double(sourceW)).rounded()))
            return (w, h)

        case (nil, let h?):
            let w = max(1, Int((Double(sourceW) * Double(h) / Double(sourceH)).rounded()))
            return (w, h)

        case (let w?, let h?):
            switch spec.fit {
            case .fill, .cover:
                return (w, h)
            case .contain:
                // Fit fully inside the (w, h) box preserving aspect ratio.
                let scale = min(
                    Double(w) / Double(sourceW),
                    Double(h) / Double(sourceH)
                )
                let outW = max(1, Int((Double(sourceW) * scale).rounded()))
                let outH = max(1, Int((Double(sourceH) * scale).rounded()))
                return (outW, outH)
            }
        }
    }

    private func renderScaled(
        _ source: CGImage,
        toWidth width: Int,
        toHeight height: Int
    ) throws -> RasterImage {
        guard width > 0, height > 0 else {
            throw SwiftMageXError.raster("target dimensions must be positive")
        }
        let context = CIContext(options: nil)
        let ciImage = CIImage(cgImage: source)

        // Use Lanczos for high-quality scaling. CILanczosScaleTransform takes
        // an isotropic scale plus aspect ratio; compute both from the target.
        let scaleY = Double(height) / Double(source.height)
        let aspectRatio = (Double(width) / Double(source.width)) / scaleY

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            throw SwiftMageXError.raster("CILanczosScaleTransform unavailable")
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scaleY, forKey: kCIInputScaleKey)
        filter.setValue(aspectRatio, forKey: kCIInputAspectRatioKey)

        guard let output = filter.outputImage else {
            throw SwiftMageXError.raster("Lanczos filter produced no output")
        }

        // Lanczos can produce subpixel extents; render into an explicit rect.
        let renderRect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let rendered = context.createCGImage(output, from: renderRect) else {
            throw SwiftMageXError.raster("failed to render scaled image")
        }
        return RasterImage(cgImage: rendered)
    }

    private func mergeMetadata(
        _ metadata: ImageMetadata,
        into properties: inout [CFString: Any],
        format: ImageFormat
    ) {
        // Milestone 5 owns the full embedding; today the call site stays stable
        // and PNGs gain a best-effort tEXt dictionary.
        guard format == .png else { return }
        var png: [CFString: Any] = (properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]) ?? [:]
        if let prompt = metadata.prompt {
            png["Prompt" as CFString] = prompt
        }
        if let model = metadata.model {
            png["Model" as CFString] = model
        }
        if let seed = metadata.seed {
            png["Seed" as CFString] = String(seed)
        }
        png["Timestamp" as CFString] = ISO8601DateFormatter().string(from: metadata.timestamp)
        png["ToolVersion" as CFString] = metadata.toolVersion
        properties[kCGImagePropertyPNGDictionary] = png
    }
}

// MARK: - ImageFormat detection

extension ImageFormat {
    /// Detects the format of the file at `url` from its UTI.
    ///
    /// PNG and JPEG round-trip; HEIC and WebP — readable by ImageIO but not
    /// writable by 0.1 — return `nil` so the caller can fall back to a
    /// supported default (typically PNG).
    public static func detect(at url: URL) -> ImageFormat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rawUTI = CGImageSourceGetType(source) as String? else {
            return nil
        }
        guard let type = UTType(rawUTI) else { return nil }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        return nil
    }
}
