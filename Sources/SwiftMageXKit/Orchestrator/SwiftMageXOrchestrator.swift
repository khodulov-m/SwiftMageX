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

    public init(path: URL, format: ImageFormat, width: Int, height: Int) {
        self.path = path
        self.format = format
        self.width = width
        self.height = height
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
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) async throws -> [WrittenImage] {
        let images = try await provider.generate(request)
        guard !images.isEmpty else {
            throw SwiftMageXError.provider("provider returned no images")
        }

        let urls = try OutputPath.resolve(
            target: output,
            count: images.count,
            format: .png,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )

        return try zip(images, urls).map { (image, url) in
            try writeOne(
                image: image,
                to: url,
                request: request,
                engine: engine,
                timestamp: timestamp
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
        if let frame = frame {
            let frameURL = absoluteFileURL(frame, currentDirectoryPath: currentDirectoryPath)
            guard FileManager.default.fileExists(atPath: frameURL.path) else {
                throw SwiftMageXError.io("frame file not found: \(frameURL.path)")
            }
            let frameImage = try engine.load(from: frameURL)
            framedDevice = try engine.frameScreenshot(rawScreenshot, in: frameImage, frameSpec)
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

    private static func writeOne(
        image: GeneratedImage,
        to url: URL,
        request: GenerationRequest,
        engine: any RasterEngine,
        timestamp: Date
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
            height: raster.height
        )
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
}
