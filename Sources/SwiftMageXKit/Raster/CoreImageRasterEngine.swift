import CoreGraphics
import CoreImage
import CoreText
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

    // MARK: - Overlay text

    /// Safe-zone padding as a fraction of each image edge (spec §9, §6.3).
    private static let safeZoneFraction: CGFloat = 0.05

    public func overlayText(_ image: RasterImage, _ spec: TextSpec) throws -> RasterImage {
        // Validate hex colors at the kit boundary so bad input is .invalidInput
        // rather than a half-rendered raster failure (spec §13).
        guard let fillColor = Self.parseHexColor(spec.color) else {
            throw SwiftMageXError.invalidInput("invalid hex color: \(spec.color)")
        }
        var strokeColor: CGColor? = nil
        if let raw = spec.strokeColor {
            guard let parsed = Self.parseHexColor(raw) else {
                throw SwiftMageXError.invalidInput("invalid hex color: \(raw)")
            }
            strokeColor = parsed
        }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw SwiftMageXError.raster("source image has zero dimensions")
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SwiftMageXError.raster("unable to create bitmap context")
        }

        // Draw the source image as the background. CGContext uses a bottom-up
        // coordinate system; CGContext.draw flips internally so the visible
        // result matches the input.
        context.draw(
            image.cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        // Build the styled string.
        let font = Self.makeFont(name: spec.fontName, size: CGFloat(spec.fontSize))
        let alignment: CTTextAlignment
        switch spec.position {
        case .topLeft, .bottomLeft: alignment = .left
        case .topRight, .bottomRight: alignment = .right
        case .top, .bottom, .center: alignment = .center
        }
        var alignmentValue = alignment
        let paragraph: CTParagraphStyle = withUnsafePointer(to: &alignmentValue) { ptr in
            var setting = CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: UnsafeRawPointer(ptr)
            )
            return CTParagraphStyleCreate(&setting, 1)
        }

        var attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: fillColor,
            kCTParagraphStyleAttributeName: paragraph,
        ]
        if let strokeColor = strokeColor {
            attributes[kCTStrokeColorAttributeName] = strokeColor
            // A negative width tells CoreText to stroke *and* fill — that's the
            // intended behavior per spec §6.3 (stroke is in addition to fill).
            attributes[kCTStrokeWidthAttributeName] = -spec.strokeWidth
        }

        let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            spec.text as CFString,
            attributes as CFDictionary
        )!

        // Compute the safe zone and lay out the text inside it.
        let padX = CGFloat(width) * Self.safeZoneFraction
        let padY = CGFloat(height) * Self.safeZoneFraction
        let safeWidth = max(1, CGFloat(width) - 2 * padX)
        let safeHeight = max(1, CGFloat(height) - 2 * padY)

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let fullRange = CFRange(location: 0, length: CFAttributedStringGetLength(attributed))
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            fullRange,
            nil,
            CGSize(width: safeWidth, height: .greatestFiniteMagnitude),
            nil
        )
        // Clamp the height to the safe zone — long text gets truncated rather
        // than spilling onto the edge of the image.
        let textWidth = min(suggested.width, safeWidth)
        let textHeight = min(suggested.height, safeHeight)

        let origin = Self.frameOrigin(
            position: spec.position,
            imageWidth: CGFloat(width),
            imageHeight: CGFloat(height),
            textWidth: textWidth,
            textHeight: textHeight,
            padX: padX,
            padY: padY
        )

        let framePath = CGPath(
            rect: CGRect(x: origin.x, y: origin.y, width: textWidth, height: textHeight),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(framesetter, fullRange, framePath, nil)
        CTFrameDraw(frame, context)

        guard let output = context.makeImage() else {
            throw SwiftMageXError.raster("text overlay rendering failed")
        }
        return RasterImage(cgImage: output)
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

    /// Parses a `#RRGGBB` or `#RRGGBBAA` string into a `CGColor`.
    ///
    /// Returns `nil` for any malformed input — including missing `#`, the
    /// wrong digit count, or non-hex characters. Internal so the test target
    /// can drive it via the engine's public `overlayText` path.
    static func parseHexColor(_ raw: String) -> CGColor? {
        guard raw.hasPrefix("#") else { return nil }
        let hex = raw.dropFirst()
        guard hex.count == 6 || hex.count == 8 else { return nil }
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }

        var value: UInt64 = 0
        let scanner = Scanner(string: String(hex))
        guard scanner.scanHexInt64(&value) else { return nil }

        let r, g, b, a: CGFloat
        if hex.count == 6 {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1.0
        } else {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        return CGColor(colorSpace: cs, components: [r, g, b, a])
    }

    private static func makeFont(name: String?, size: CGFloat) -> CTFont {
        if let name = name {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        return CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    /// Bottom-left corner (CG coords, y-up) of the text frame for `position`.
    ///
    /// The image has a 5% safe zone on each edge. Within that safe zone, the
    /// frame is anchored to the edge or corner named by `position`, with
    /// horizontal centering for `top`/`bottom`/`center`.
    private static func frameOrigin(
        position: TextPosition,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        textWidth: CGFloat,
        textHeight: CGFloat,
        padX: CGFloat,
        padY: CGFloat
    ) -> CGPoint {
        let xCenter = (imageWidth - textWidth) / 2
        let xLeft = padX
        let xRight = imageWidth - padX - textWidth
        let yTop = imageHeight - padY - textHeight
        let yBottom = padY
        let yCenter = (imageHeight - textHeight) / 2

        switch position {
        case .top: return CGPoint(x: xCenter, y: yTop)
        case .center: return CGPoint(x: xCenter, y: yCenter)
        case .bottom: return CGPoint(x: xCenter, y: yBottom)
        case .topLeft: return CGPoint(x: xLeft, y: yTop)
        case .topRight: return CGPoint(x: xRight, y: yTop)
        case .bottomLeft: return CGPoint(x: xLeft, y: yBottom)
        case .bottomRight: return CGPoint(x: xRight, y: yBottom)
        }
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
