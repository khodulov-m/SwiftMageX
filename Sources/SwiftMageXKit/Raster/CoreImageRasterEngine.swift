import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

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

    // MARK: - Composite

    public func composite(
        _ foreground: RasterImage,
        onto background: RasterImage,
        _ spec: CompositeSpec
    ) throws -> RasterImage {
        let bgW = background.width
        let bgH = background.height
        guard bgW > 0, bgH > 0 else {
            throw SwiftMageXError.raster("background image has zero dimensions")
        }
        let fgW = foreground.width
        let fgH = foreground.height
        guard fgW > 0, fgH > 0 else {
            throw SwiftMageXError.raster("foreground image has zero dimensions")
        }
        guard spec.scale > 0 else {
            throw SwiftMageXError.invalidInput("composite scale must be positive (got \(spec.scale))")
        }

        // Contain-fit the foreground into a box of `scale × background`,
        // preserving aspect ratio.
        let box = min(
            Double(bgW) * spec.scale / Double(fgW),
            Double(bgH) * spec.scale / Double(fgH)
        )
        let drawW = max(1, Int((Double(fgW) * box).rounded()))
        let drawH = max(1, Int((Double(fgH) * box).rounded()))

        // Anchor with no safe-zone padding, then apply the pixel nudges.
        // CoreGraphics is y-up, so a positive `offsetY` (down) subtracts.
        let origin = Self.frameOrigin(
            position: spec.position,
            imageWidth: CGFloat(bgW),
            imageHeight: CGFloat(bgH),
            textWidth: CGFloat(drawW),
            textHeight: CGFloat(drawH),
            padX: 0,
            padY: 0
        )
        let drawRect = CGRect(
            x: origin.x + CGFloat(spec.offsetX),
            y: origin.y - CGFloat(spec.offsetY),
            width: CGFloat(drawW),
            height: CGFloat(drawH)
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: bgW,
            height: bgH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SwiftMageXError.raster("unable to create bitmap context")
        }
        context.interpolationQuality = .high
        context.draw(
            background.cgImage,
            in: CGRect(x: 0, y: 0, width: bgW, height: bgH)
        )
        context.setAlpha(CGFloat(max(0, min(1, spec.opacity))))
        context.draw(foreground.cgImage, in: drawRect)
        context.setAlpha(1)

        guard let output = context.makeImage() else {
            throw SwiftMageXError.raster("composite rendering failed")
        }
        return RasterImage(cgImage: output)
    }

    // MARK: - Device framing

    public func frameScreenshot(
        _ screenshot: RasterImage,
        in frame: RasterImage,
        _ spec: DeviceFrameSpec
    ) throws -> RasterImage {
        let frameW = frame.width
        let frameH = frame.height
        guard frameW > 0, frameH > 0 else {
            throw SwiftMageXError.raster("frame image has zero dimensions")
        }

        let rect: DeviceFrameSpec.ScreenRect
        if let explicit = spec.screenRect {
            rect = explicit
        } else if let detected = Self.detectScreenRect(
            in: frame.cgImage,
            alphaThreshold: spec.alphaThreshold
        ) {
            rect = detected
        } else {
            throw SwiftMageXError.invalidInput(
                "frame has no enclosed transparent screen area; pass an explicit screen rect"
            )
        }

        guard rect.width > 0, rect.height > 0,
              rect.x >= 0, rect.y >= 0,
              rect.x + rect.width <= frameW,
              rect.y + rect.height <= frameH else {
            throw SwiftMageXError.invalidInput(
                "screen rect \(rect.x),\(rect.y),\(rect.width),\(rect.height) lies outside the \(frameW)x\(frameH) frame"
            )
        }

        // Scale the screenshot into the screen rect (cover by default).
        let scaled = try resize(
            screenshot,
            to: ResizeSpec(width: rect.width, height: rect.height, fit: spec.screenFit)
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: frameW,
            height: frameH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SwiftMageXError.raster("unable to create bitmap context")
        }
        context.interpolationQuality = .high

        // Place the screenshot under the bezel. The screen rect is top-left
        // origin; convert to CoreGraphics' bottom-up space. `.contain` may
        // yield an image smaller than the rect, so center it inside the rect.
        let drawW = scaled.width
        let drawH = scaled.height
        let cgX = CGFloat(rect.x) + (CGFloat(rect.width) - CGFloat(drawW)) / 2
        let cgY = CGFloat(frameH - rect.y - rect.height)
            + (CGFloat(rect.height) - CGFloat(drawH)) / 2
        context.draw(
            scaled.cgImage,
            in: CGRect(x: cgX, y: cgY, width: CGFloat(drawW), height: CGFloat(drawH))
        )
        // Bezel on top — its opaque area masks the screenshot's corners.
        context.draw(frame.cgImage, in: CGRect(x: 0, y: 0, width: frameW, height: frameH))

        guard let output = context.makeImage() else {
            throw SwiftMageXError.raster("device framing failed")
        }
        return RasterImage(cgImage: output)
    }

    // MARK: - Remove background

    public func removeBackground(_ image: RasterImage) throws -> RasterImage {
        let source = image.cgImage
        guard source.width > 0, source.height > 0 else {
            throw SwiftMageXError.raster("source image has zero dimensions")
        }

        // Vision's foreground-instance segmentation (macOS 14+) runs the
        // built-in on-device model — no network, no provider quota.
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: source, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw SwiftMageXError.raster("foreground segmentation failed: \(error.localizedDescription)")
        }

        // No observation, or an observation with no instances, means the model
        // found nothing salient to keep — surface that as a raster failure
        // rather than writing a fully transparent image.
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw SwiftMageXError.raster("no foreground subject detected")
        }

        let masked: CVPixelBuffer
        do {
            // Composite every detected instance over transparency, at the
            // source resolution (not cropped to the subject's bounding box).
            masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
        } catch {
            throw SwiftMageXError.raster("mask compositing failed: \(error.localizedDescription)")
        }

        // The masked buffer is BGRA with a populated alpha channel; render it
        // back to a CGImage so the rest of the pipeline is format-agnostic.
        let ciImage = CIImage(cvPixelBuffer: masked)
        let context = CIContext(options: nil)
        guard let output = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw SwiftMageXError.raster("could not render masked image")
        }
        return RasterImage(cgImage: output)
    }

    // MARK: - Smart crop

    public func smartCrop(_ image: RasterImage, _ spec: SmartCropSpec) throws -> RasterImage {
        guard spec.aspectWidth > 0, spec.aspectHeight > 0 else {
            throw SwiftMageXError.invalidInput(
                "aspect ratio must be positive (got \(spec.aspectWidth):\(spec.aspectHeight))"
            )
        }

        let source = image.cgImage
        let sourceW = source.width
        let sourceH = source.height
        guard sourceW > 0, sourceH > 0 else {
            throw SwiftMageXError.raster("source image has zero dimensions")
        }

        // Largest aspectW:aspectH rect that fits inside the source. Compare
        // ratios as Doubles to avoid integer-division surprises on odd sizes.
        let srcRatio = Double(sourceW) / Double(sourceH)
        let targetRatio = Double(spec.aspectWidth) / Double(spec.aspectHeight)
        let cropW: Int
        let cropH: Int
        if targetRatio >= srcRatio {
            cropW = sourceW
            cropH = max(1, Int((Double(sourceW) * Double(spec.aspectHeight) / Double(spec.aspectWidth)).rounded()))
        } else {
            cropH = sourceH
            cropW = max(1, Int((Double(sourceH) * Double(spec.aspectWidth) / Double(spec.aspectHeight)).rounded()))
        }

        // Vision's attention saliency (macOS 10.15+) runs the built-in
        // on-device model — no network, no provider quota.
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: source, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw SwiftMageXError.raster("attention saliency failed: \(error.localizedDescription)")
        }

        // Saliency center in image-pixel coordinates (top-left origin). Vision
        // normalizes bounding boxes to [0,1] with a bottom-left origin, so the
        // Y component is flipped on the way out.
        let centerX: Double
        let centerY: Double
        if let observation = request.results?.first,
           let salientObjects = observation.salientObjects,
           !salientObjects.isEmpty {
            var union = salientObjects[0].boundingBox
            for object in salientObjects.dropFirst() {
                union = union.union(object.boundingBox)
            }
            let normCenterX = union.midX
            let normCenterY = union.midY
            centerX = Double(sourceW) * Double(normCenterX)
            centerY = Double(sourceH) * (1.0 - Double(normCenterY))
        } else {
            // Flat / uniform images may yield no salient objects — fall back
            // to a center crop so the requested aspect ratio still holds.
            centerX = Double(sourceW) / 2.0
            centerY = Double(sourceH) / 2.0
        }

        let maxX = sourceW - cropW
        let maxY = sourceH - cropH
        let rawX = Int((centerX - Double(cropW) / 2.0).rounded())
        let rawY = Int((centerY - Double(cropH) / 2.0).rounded())
        let originX = min(max(0, rawX), max(0, maxX))
        let originY = min(max(0, rawY), max(0, maxY))

        let rect = CGRect(x: originX, y: originY, width: cropW, height: cropH)
        guard let cropped = source.cropping(to: rect) else {
            throw SwiftMageXError.raster("smart crop failed")
        }
        return RasterImage(cgImage: cropped)
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

    /// Finds the enclosed transparent screen cutout in a device-frame image.
    ///
    /// The frame's *outer* transparency (around the device body) reaches the
    /// image border, while the screen hole is fully surrounded by opaque bezel.
    /// We flood-fill transparent pixels inward from the border to tag them as
    /// "outside", then take the bounding box of the transparent pixels that
    /// remain — that box is the screen rect (top-left origin). Returns `nil`
    /// when no enclosed transparent region exists.
    static func detectScreenRect(
        in image: CGImage,
        alphaThreshold: Int
    ) -> DeviceFrameSpec.ScreenRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        // Memory row 0 is the top scanline; alpha is the last byte of each RGBA
        // pixel (premultipliedLast).
        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        let threshold = UInt8(max(0, min(255, alphaThreshold)))
        @inline(__always) func isTransparent(_ x: Int, _ y: Int) -> Bool {
            pixels[y * rowBytes + x * 4 + 3] < threshold
        }

        // Tag border-connected transparent pixels ("outside") via 4-neighbor
        // flood fill with an explicit stack.
        var outside = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        @inline(__always) func push(_ x: Int, _ y: Int) {
            let idx = y * width + x
            if !outside[idx] && isTransparent(x, y) {
                outside[idx] = true
                stack.append(idx)
            }
        }
        for x in 0..<width {
            push(x, 0)
            push(x, height - 1)
        }
        for y in 0..<height {
            push(0, y)
            push(width - 1, y)
        }
        while let idx = stack.popLast() {
            let x = idx % width
            let y = idx / width
            if x > 0 { push(x - 1, y) }
            if x < width - 1 { push(x + 1, y) }
            if y > 0 { push(x, y - 1) }
            if y < height - 1 { push(x, y + 1) }
        }

        // Bounding box of enclosed (transparent but not outside) pixels.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let rowBase = y * width
            for x in 0..<width where isTransparent(x, y) && !outside[rowBase + x] {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return DeviceFrameSpec.ScreenRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    /// Pack the structured metadata into a single JSON object — the same shape
    /// for both formats so a reader can parse it without caring whether it's
    /// PNG or JPEG.
    ///
    /// ImageIO only surfaces a fixed set of documented keys back through
    /// `kCGImagePropertyPNGDictionary` on read; arbitrary custom keys are
    /// silently dropped. So the canonical home is a standard text slot
    /// (`kCGImagePropertyPNGDescription` for PNG, `kCGImagePropertyExifUserComment`
    /// for JPEG) with a JSON payload that re-parses cleanly.
    private func mergeMetadata(
        _ metadata: ImageMetadata,
        into properties: inout [CFString: Any],
        format: ImageFormat
    ) {
        let timestamp = ISO8601DateFormatter().string(from: metadata.timestamp)
        var payload: [String: Any] = [
            "timestamp": timestamp,
            "toolVersion": metadata.toolVersion,
        ]
        if let prompt = metadata.prompt { payload["prompt"] = prompt }
        if let model = metadata.model { payload["model"] = model }
        if let seed = metadata.seed { payload["seed"] = String(seed) }
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let blob = String(data: json, encoding: .utf8) else {
            return
        }
        let software = "swiftmagex/\(metadata.toolVersion)"

        switch format {
        case .png:
            var png: [CFString: Any] = (properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]) ?? [:]
            png[kCGImagePropertyPNGDescription] = blob
            png[kCGImagePropertyPNGSoftware] = software
            properties[kCGImagePropertyPNGDictionary] = png

        case .jpeg:
            var exif: [CFString: Any] = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
            exif[kCGImagePropertyExifUserComment] = blob
            properties[kCGImagePropertyExifDictionary] = exif

            var tiff: [CFString: Any] = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
            tiff[kCGImagePropertyTIFFSoftware] = software
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
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
