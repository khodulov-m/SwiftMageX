import CoreGraphics
import Foundation
import ImageIO

/// A single image written to disk — what every orchestrator call returns.
///
/// Carries enough information for the CLI's JSON output schema (path, format,
/// dimensions per spec §12) and for the MCP server (milestone 7) to attach
/// content blocks alongside the path.
public struct WrittenImage: Sendable, Equatable {
    public let path: URL
    public let format: ImageFormat
    public let width: Int
    public let height: Int
    /// True when this image was served from a ``ResponseCache`` hit rather
    /// than a fresh provider call. Always `false` for local-only ops
    /// (`resize`, `text`, `composite`, `appstore`, `remove-bg`, `crop`) and
    /// for `generate` / `edit` runs without a cache configured.
    public let wasCached: Bool

    public init(
        path: URL,
        format: ImageFormat,
        width: Int,
        height: Int,
        wasCached: Bool = false
    ) {
        self.path = path
        self.format = format
        self.width = width
        self.height = height
        self.wasCached = wasCached
    }
}

/// The kit-level entry point shared by the CLI and the MCP server.
///
/// Both frontends are intentionally thin — argument parsing or MCP protocol
/// only — and dispatch into this enum so the pipeline (provider call →
/// output-path resolution → metadata embedding → disk write) exists in
/// exactly one place.
public enum SwiftMageXOrchestrator {
    /// Run a full generation pipeline using the production ``GeminiProvider``
    /// and the process environment for API-key resolution.
    ///
    /// - Returns: One ``WrittenImage`` per provider output, in the order the
    ///   provider returned them. Paths are absolute.
    /// - Throws: ``SwiftMageXError/configuration(_:)`` when no API key is set,
    ///   propagating provider / raster / I/O errors otherwise.
    public static func generate(
        request: GenerationRequest,
        output: String?,
        cache: (any ResponseCache)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) async throws -> [WrittenImage] {
        guard let apiKey = Configuration.resolvedAPIKey(in: environment) else {
            throw SwiftMageXError.configuration(
                "missing \(Configuration.EnvironmentKey.primaryAPIKey)"
            )
        }
        let provider = makeProvider(for: request.model, apiKey: apiKey)
        return try await generate(
            request: request,
            output: output,
            provider: provider,
            cache: cache,
            engine: engine,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )
    }

    /// Variant with an injectable ``ImageProvider`` — used by the kit's own
    /// tests and by the MCP server (milestone 7) when a different provider is
    /// wired in.
    public static func generate(
        request: GenerationRequest,
        output: String?,
        provider: any ImageProvider,
        cache: (any ResponseCache)? = nil,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) async throws -> [WrittenImage] {
        let resolved = try await fetchOrCache(request: request, provider: provider, cache: cache)

        let urls = try OutputPath.resolve(
            target: output,
            count: resolved.images.count,
            format: .png,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )

        return try zip(resolved.images, urls).map { (image, url) in
            try writeOne(
                image: image,
                to: url,
                request: request,
                engine: engine,
                timestamp: timestamp,
                wasCached: resolved.wasCached
            )
        }
    }

    /// Run an image-to-image / multi-image edit through Gemini
    /// (`:generateContent` with `inlineData` parts). `input` is the primary
    /// source image; `references` is an optional list of additional reference
    /// images the prompt can compose against; an optional `mask` is sent as a
    /// final image part (white = edit region, black = preserve).
    ///
    /// Mirrors the production / testable split that ``generate(request:output:environment:engine:timestamp:currentDirectoryPath:)``
    /// uses: this overload resolves the API key from the environment and
    /// constructs a provider; the variant below accepts an injected provider.
    ///
    /// - Throws: ``SwiftMageXError/configuration(_:)`` when no API key is set,
    ///   ``SwiftMageXError/invalidInput(_:)`` for a non-Gemini model or an
    ///   unsupported input format, ``SwiftMageXError/io(_:)`` when an input
    ///   file is missing, and provider / raster errors otherwise.
    public static func edit(
        input: String,
        references: [String] = [],
        mask: String?,
        request: GenerationRequest,
        output: String?,
        cache: (any ResponseCache)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) async throws -> [WrittenImage] {
        guard let apiKey = Configuration.resolvedAPIKey(in: environment) else {
            throw SwiftMageXError.configuration(
                "missing \(Configuration.EnvironmentKey.primaryAPIKey)"
            )
        }
        let provider = makeProvider(for: request.model, apiKey: apiKey)
        return try await edit(
            input: input,
            references: references,
            mask: mask,
            request: request,
            output: output,
            provider: provider,
            cache: cache,
            engine: engine,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )
    }

    /// Variant with an injectable ``ImageProvider`` — used by the kit's own
    /// tests and by the MCP server.
    public static func edit(
        input: String,
        references: [String] = [],
        mask: String?,
        request: GenerationRequest,
        output: String?,
        provider: any ImageProvider,
        cache: (any ResponseCache)? = nil,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) async throws -> [WrittenImage] {
        guard ModelCatalog.family(for: request.model) == .gemini else {
            throw SwiftMageXError.invalidInput(
                "edit requires a Gemini model (got \(request.model))"
            )
        }

        var referenceImages: [ReferenceImage] = []
        referenceImages.reserveCapacity(1 + references.count)
        referenceImages.append(try loadReference(
            path: input,
            role: "input",
            currentDirectoryPath: currentDirectoryPath
        ))
        for path in references {
            referenceImages.append(try loadReference(
                path: path,
                role: "reference",
                currentDirectoryPath: currentDirectoryPath
            ))
        }

        var maskData: Data?
        var maskMime: String?
        if let mask = mask {
            let maskURL = absoluteFileURL(mask, currentDirectoryPath: currentDirectoryPath)
            guard FileManager.default.fileExists(atPath: maskURL.path) else {
                throw SwiftMageXError.io("mask file not found: \(maskURL.path)")
            }
            guard let format = ImageFormat.detect(at: maskURL) else {
                throw SwiftMageXError.invalidInput(
                    "unsupported mask format at \(maskURL.path); use PNG or JPEG"
                )
            }
            maskData = try readImageBytes(at: maskURL)
            maskMime = format.mimeType
        }

        var augmented = request
        augmented.referenceImages = referenceImages
        augmented.mask = maskData
        augmented.maskMimeType = maskMime

        let resolved = try await fetchOrCache(request: augmented, provider: provider, cache: cache)

        let urls = try OutputPath.resolve(
            target: output,
            count: resolved.images.count,
            format: .png,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )

        return try zip(resolved.images, urls).map { image, url in
            try writeOne(
                image: image,
                to: url,
                request: augmented,
                engine: engine,
                timestamp: timestamp,
                wasCached: resolved.wasCached
            )
        }
    }

    /// Run a single local resize/crop/conversion through the raster engine.
    ///
    /// Mirrors `swiftmagex resize` (spec §6.2). `input` is interpreted relative
    /// to `currentDirectoryPath` when not absolute; `output` may be `nil` (in
    /// which case the result lands next to the source per spec §6.2).
    ///
    /// - Throws: ``SwiftMageXError/io(_:)`` when the input is missing,
    ///   ``SwiftMageXError/invalidInput(_:)`` for inconsistent spec, and
    ///   ``SwiftMageXError/raster(_:)`` for pipeline failures.
    public static func resize(
        input: String,
        spec: ResizeSpec,
        output: String?,
        format: ImageFormat?,
        quality: Double,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> WrittenImage {
        let inputURL = absoluteFileURL(input, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw SwiftMageXError.io("input file not found: \(inputURL.path)")
        }

        let resolvedFormat = format ?? ImageFormat.detect(at: inputURL) ?? .png
        let image = try engine.load(from: inputURL)
        let resized = try engine.resize(image, to: spec)
        let outputURL = try OutputPath.resolveSingle(
            target: output,
            sourceURL: inputURL,
            format: resolvedFormat,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )
        try engine.write(
            resized,
            to: outputURL,
            format: resolvedFormat,
            quality: quality,
            metadata: nil
        )
        return WrittenImage(
            path: outputURL,
            format: resolvedFormat,
            width: resized.width,
            height: resized.height
        )
    }

    /// Run a single text overlay through the raster engine.
    ///
    /// Mirrors `swiftmagex text` (spec §6.3). Output format follows the source
    /// file's UTI (PNG by default when the source is unwritable, e.g. HEIC).
    public static func overlayText(
        input: String,
        spec: TextSpec,
        output: String?,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> WrittenImage {
        let inputURL = absoluteFileURL(input, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw SwiftMageXError.io("input file not found: \(inputURL.path)")
        }

        let resolvedFormat = ImageFormat.detect(at: inputURL) ?? .png
        let image = try engine.load(from: inputURL)
        let rendered = try engine.overlayText(image, spec)
        let outputURL = try OutputPath.resolveSingle(
            target: output,
            sourceURL: inputURL,
            format: resolvedFormat,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )
        try engine.write(
            rendered,
            to: outputURL,
            format: resolvedFormat,
            quality: 0.9,
            metadata: nil
        )
        return WrittenImage(
            path: outputURL,
            format: resolvedFormat,
            width: rendered.width,
            height: rendered.height
        )
    }

    /// Alpha-composite one local image onto another.
    ///
    /// Mirrors `swiftmagex composite`. `input` is the background, `overlay` the
    /// foreground; both are interpreted relative to `currentDirectoryPath` when
    /// not absolute. Output follows the same rules as ``resize(input:spec:output:format:quality:engine:timestamp:currentDirectoryPath:)``.
    public static func composite(
        input: String,
        overlay: String,
        spec: CompositeSpec,
        output: String?,
        format: ImageFormat?,
        quality: Double,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> WrittenImage {
        let backgroundURL = absoluteFileURL(input, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: backgroundURL.path) else {
            throw SwiftMageXError.io("input file not found: \(backgroundURL.path)")
        }
        let overlayURL = absoluteFileURL(overlay, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: overlayURL.path) else {
            throw SwiftMageXError.io("overlay file not found: \(overlayURL.path)")
        }

        let resolvedFormat = format ?? ImageFormat.detect(at: backgroundURL) ?? .png
        let background = try engine.load(from: backgroundURL)
        let foreground = try engine.load(from: overlayURL)
        let composed = try engine.composite(foreground, onto: background, spec)
        let outputURL = try OutputPath.resolveSingle(
            target: output,
            sourceURL: backgroundURL,
            format: resolvedFormat,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )
        try engine.write(
            composed,
            to: outputURL,
            format: resolvedFormat,
            quality: quality,
            metadata: nil
        )
        return WrittenImage(
            path: outputURL,
            format: resolvedFormat,
            width: composed.width,
            height: composed.height
        )
    }

    /// Assemble App Store Connect screenshots, batched across device sizes.
    ///
    /// Mirrors `swiftmagex appstore`. The screenshot is framed once (when a
    /// device `frame` bezel is given) and reused; for each device the
    /// `background` is filled (cover) to the exact ASC pixel size, the framed
    /// device is composited on top, an optional `caption` is overlaid, and the
    /// result is written to a directory named `appstore_{deviceId}_{W}x{H}.png`.
    ///
    /// - Throws: ``SwiftMageXError/io(_:)`` for missing inputs,
    ///   ``SwiftMageXError/invalidInput(_:)`` for an empty device list or a
    ///   non-directory output, propagating raster errors otherwise.
    public static func prepareAppStoreScreenshots(
        screenshot: String,
        background: String,
        frame: String?,
        frameSpec: DeviceFrameSpec = DeviceFrameSpec(),
        caption: TextSpec?,
        devices: [ASCDeviceSize],
        placement: CompositeSpec,
        orientation: Orientation = .portrait,
        output: String?,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> [WrittenImage] {
        guard !devices.isEmpty else {
            throw SwiftMageXError.invalidInput("no target devices specified")
        }
        let screenshotURL = absoluteFileURL(screenshot, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            throw SwiftMageXError.io("screenshot file not found: \(screenshotURL.path)")
        }
        let backgroundURL = absoluteFileURL(background, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: backgroundURL.path) else {
            throw SwiftMageXError.io("background file not found: \(backgroundURL.path)")
        }

        let rawScreenshot = try engine.load(from: screenshotURL)
        // Frame the screenshot once and reuse it across every device size.
        let framedDevice: RasterImage
        if let resolved = try resolveFrame(
            frame: frame,
            devices: devices,
            currentDirectoryPath: currentDirectoryPath
        ) {
            let frameImage = try engine.load(from: resolved.url)
            // Caller-supplied screenRect wins; bundled-frame rect is used only
            // when the caller didn't specify one; falls through to alpha
            // auto-detection otherwise.
            let effectiveSpec: DeviceFrameSpec
            if frameSpec.screenRect != nil || resolved.screenRect == nil {
                effectiveSpec = frameSpec
            } else {
                effectiveSpec = DeviceFrameSpec(
                    screenRect: resolved.screenRect,
                    alphaThreshold: frameSpec.alphaThreshold,
                    screenFit: frameSpec.screenFit
                )
            }
            framedDevice = try engine.frameScreenshot(rawScreenshot, in: frameImage, effectiveSpec)
        } else {
            framedDevice = rawScreenshot
        }
        let backgroundImage = try engine.load(from: backgroundURL)

        let names = devices.map { device -> String in
            let dims = device.dimensions(for: orientation)
            return "appstore_\(device.id)_\(dims.width)x\(dims.height)"
        }
        let urls = try OutputPath.resolveNamed(
            target: output,
            names: names,
            format: .png,
            currentDirectoryPath: currentDirectoryPath
        )

        // The caption text doubles as the embedded prompt so each asset stays
        // self-documenting (spec §12).
        let metadata = ImageMetadata(
            prompt: caption?.text,
            model: nil,
            seed: nil,
            timestamp: timestamp,
            toolVersion: Configuration.toolVersion
        )

        return try zip(devices, urls).map { device, url in
            let dims = device.dimensions(for: orientation)
            let canvas = try engine.resize(
                backgroundImage,
                to: ResizeSpec(width: dims.width, height: dims.height, fit: .cover)
            )
            var composed = try engine.composite(framedDevice, onto: canvas, placement)
            if let caption = caption {
                composed = try engine.overlayText(composed, caption)
            }
            try engine.write(composed, to: url, format: .png, quality: 1.0, metadata: metadata)
            return WrittenImage(
                path: url,
                format: .png,
                width: composed.width,
                height: composed.height
            )
        }
    }

    /// Remove an image's background locally with Vision, leaving the salient
    /// foreground subject on transparency.
    ///
    /// No AI provider and no API key — segmentation is on-device. The output is
    /// always PNG because the cutout carries an alpha channel; a non-`.png`
    /// `output` extension is coerced to `.png` so the file name matches its
    /// content. `input` is interpreted relative to `currentDirectoryPath` when
    /// not absolute.
    ///
    /// - Throws: ``SwiftMageXError/io(_:)`` when the input is missing and
    ///   ``SwiftMageXError/raster(_:)`` when no subject is found or the pipeline
    ///   fails.
    public static func removeBackground(
        input: String,
        output: String?,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> WrittenImage {
        let inputURL = absoluteFileURL(input, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw SwiftMageXError.io("input file not found: \(inputURL.path)")
        }

        let image = try engine.load(from: inputURL)
        let cutout = try engine.removeBackground(image)

        let resolved = try OutputPath.resolveSingle(
            target: output,
            sourceURL: inputURL,
            format: .png,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )
        // Transparency requires PNG; force the extension so an explicit
        // `--output cutout.jpg` doesn't end up with PNG bytes in a .jpg file.
        let outputURL = resolved.pathExtension.lowercased() == ImageFormat.png.fileExtension
            ? resolved
            : resolved.deletingPathExtension().appendingPathExtension(ImageFormat.png.fileExtension)

        try engine.write(
            cutout,
            to: outputURL,
            format: .png,
            quality: 1.0,
            metadata: nil
        )
        return WrittenImage(
            path: outputURL,
            format: .png,
            width: cutout.width,
            height: cutout.height
        )
    }

    /// Run a saliency-driven crop through the raster engine.
    ///
    /// Crops the source to the requested aspect ratio with the crop window
    /// centered on the salient region detected by Vision's attention model.
    /// No AI provider and no API key — saliency is on-device. The output
    /// format defaults to the source format (overridable via `format`); no
    /// metadata is embedded because this is a derived raster op.
    ///
    /// - Throws: ``SwiftMageXError/io(_:)`` when the input is missing,
    ///   ``SwiftMageXError/invalidInput(_:)`` for a malformed spec, and
    ///   ``SwiftMageXError/raster(_:)`` for pipeline failures.
    public static func smartCrop(
        input: String,
        spec: SmartCropSpec,
        output: String?,
        format: ImageFormat?,
        quality: Double,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> WrittenImage {
        let inputURL = absoluteFileURL(input, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw SwiftMageXError.io("input file not found: \(inputURL.path)")
        }

        let resolvedFormat = format ?? ImageFormat.detect(at: inputURL) ?? .png
        let image = try engine.load(from: inputURL)
        let cropped = try engine.smartCrop(image, spec)
        let outputURL = try OutputPath.resolveSingle(
            target: output,
            sourceURL: inputURL,
            format: resolvedFormat,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )
        try engine.write(
            cropped,
            to: outputURL,
            format: resolvedFormat,
            quality: quality,
            metadata: nil
        )
        return WrittenImage(
            path: outputURL,
            format: resolvedFormat,
            width: cropped.width,
            height: cropped.height
        )
    }

    /// Constructs the right provider for `model` using ``ModelCatalog`` to
    /// pick between Gemini's `:generateContent` shape and Imagen's `:predict`.
    /// Exposed so the MCP frontend can share the same routing.
    public static func makeProvider(for model: String, apiKey: String) -> any ImageProvider {
        switch ModelCatalog.family(for: model) {
        case .gemini:
            return GeminiProvider(apiKey: apiKey)
        case .imagen:
            return ImagenProvider(apiKey: apiKey)
        }
    }

    // MARK: - Internals

    private static func absoluteFileURL(
        _ raw: String,
        currentDirectoryPath: String
    ) -> URL {
        let cwd = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: raw, relativeTo: cwd).standardizedFileURL
    }

    private static func readImageBytes(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw SwiftMageXError.io(
                "could not read \(url.path): \(error.localizedDescription)"
            )
        }
    }

    /// Resolves an edit input or reference path to a typed ``ReferenceImage``.
    /// `role` is used purely to disambiguate the error message ("input file
    /// not found" vs "reference file not found").
    private static func loadReference(
        path: String,
        role: String,
        currentDirectoryPath: String
    ) throws -> ReferenceImage {
        let url = absoluteFileURL(path, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SwiftMageXError.io("\(role) file not found: \(url.path)")
        }
        guard let format = ImageFormat.detect(at: url) else {
            throw SwiftMageXError.invalidInput(
                "unsupported edit \(role) format at \(url.path); use PNG or JPEG"
            )
        }
        let data = try readImageBytes(at: url)
        return ReferenceImage(data: data, mimeType: format.mimeType)
    }

    private static func writeOne(
        image: GeneratedImage,
        to url: URL,
        request: GenerationRequest,
        engine: any RasterEngine,
        timestamp: Date,
        wasCached: Bool = false
    ) throws -> WrittenImage {
        let raster = try decodeProviderImage(image)
        // The seed is recorded as user intent even when the provider did not
        // honor it — see spec §12. `image.seed` may be nil because the
        // provider stripped it; `request.seed` is the original ask.
        let metadata = ImageMetadata(
            prompt: request.prompt,
            model: request.model,
            seed: request.seed,
            timestamp: timestamp,
            toolVersion: Configuration.toolVersion
        )
        try engine.write(
            raster,
            to: url,
            format: .png,
            quality: 1.0,
            metadata: metadata
        )
        return WrittenImage(
            path: url,
            format: .png,
            width: raster.width,
            height: raster.height,
            wasCached: wasCached
        )
    }

    /// Returns provider images for `request`, served from `cache` on hit and
    /// recorded into `cache` on miss. Cache I/O is best-effort: any read
    /// failure is treated as a miss; any write failure is swallowed so a
    /// broken cache never aborts a real generation. The `wasCached` flag
    /// flows back to ``WrittenImage`` so frontends can surface it (JSON
    /// `cached: true`, `--verbose` diagnostics, etc.).
    private static func fetchOrCache(
        request: GenerationRequest,
        provider: any ImageProvider,
        cache: (any ResponseCache)?
    ) async throws -> (images: [GeneratedImage], wasCached: Bool) {
        if let cache, let hit = try? cache.lookup(CacheKey.compute(from: request)) {
            let images = hit.images.map { cached in
                GeneratedImage(
                    data: cached.data,
                    format: cached.format,
                    prompt: request.prompt,
                    model: request.model,
                    seed: request.seed
                )
            }
            guard !images.isEmpty else {
                throw SwiftMageXError.provider("cache hit contained no images")
            }
            return (images, true)
        }

        let images = try await provider.generate(request)
        guard !images.isEmpty else {
            throw SwiftMageXError.provider("provider returned no images")
        }
        if let cache {
            let response = CachedResponse(images: images.map {
                CachedImage(data: $0.data, format: $0.format)
            })
            try? cache.store(CacheKey.compute(from: request), response: response)
        }
        return (images, false)
    }

    private static func decodeProviderImage(_ image: GeneratedImage) throws -> RasterImage {
        guard let source = CGImageSourceCreateWithData(image.data as CFData, nil) else {
            throw SwiftMageXError.raster("could not open provider image bytes")
        }
        guard CGImageSourceGetCount(source) > 0,
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SwiftMageXError.raster("provider image had no decodable frame")
        }
        return RasterImage(cgImage: cg)
    }

    /// Resolves the `frame:` argument of ``prepareAppStoreScreenshots(…)`` into
    /// a concrete on-disk URL (plus an optional embedded screen rect), or
    /// `nil` when no framing should happen.
    ///
    /// Resolution order:
    /// 1. `frame == nil` → auto-pick a bundled frame for the *first* device,
    ///    or return `nil` if none is bundled for that device (current
    ///    behaviour preserved for unsupported slots).
    /// 2. `frame` matches a bundled frame id → use the bundled asset.
    /// 3. Otherwise treat it as a filesystem path.
    ///
    /// A non-empty string that's neither a known id nor an existing file
    /// surfaces as ``SwiftMageXError/io(_:)`` so the frontend can report the
    /// missing input with the same error category it already uses (spec §13).
    private static func resolveFrame(
        frame: String?,
        devices: [ASCDeviceSize],
        currentDirectoryPath: String
    ) throws -> (url: URL, screenRect: DeviceFrameSpec.ScreenRect?)? {
        guard let frame = frame else {
            // Auto-pick: only when the first requested device has a bundled
            // frame. Heterogeneous device lists fall back to "no auto-pick"
            // because a single bezel may not silhouette the others well.
            guard let firstDevice = devices.first,
                  let bundled = DeviceFrameCatalog.defaultFrame(for: firstDevice.id) else {
                return nil
            }
            let url = try bundled.url()
            return (url, bundled.screenRect)
        }

        // Explicit value — try the catalog first.
        if let bundled = DeviceFrameCatalog.frame(id: frame) {
            let url = try bundled.url()
            return (url, bundled.screenRect)
        }

        // Treat as a filesystem path; matches the previous behaviour exactly.
        let frameURL = absoluteFileURL(frame, currentDirectoryPath: currentDirectoryPath)
        guard FileManager.default.fileExists(atPath: frameURL.path) else {
            throw SwiftMageXError.io("frame file not found: \(frameURL.path)")
        }
        return (frameURL, nil)
    }
}
