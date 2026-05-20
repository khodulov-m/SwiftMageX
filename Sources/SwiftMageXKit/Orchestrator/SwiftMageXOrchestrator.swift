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
/// exactly one place. Milestone 5 introduces `generate`; milestone 7 adds
/// `resize` and `overlayText` and migrates the local commands to call here too.
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
        let provider = GeminiProvider(apiKey: apiKey)
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

    // MARK: - Internals

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
