import CoreGraphics
import Foundation
import ImageIO

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
    /// - Returns: Absolute file URLs of every written image, in the order the
    ///   provider returned them.
    /// - Throws: ``SwiftMageXError/configuration(_:)`` when no API key is set,
    ///   propagating provider / raster / I/O errors otherwise.
    public static func generate(
        request: GenerationRequest,
        output: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        engine: any RasterEngine = CoreImageRasterEngine(),
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) async throws -> [URL] {
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
    ) async throws -> [URL] {
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

        for (image, url) in zip(images, urls) {
            try writeOne(
                image: image,
                to: url,
                request: request,
                engine: engine,
                timestamp: timestamp
            )
        }
        return urls
    }

    // MARK: - Internals

    private static func writeOne(
        image: GeneratedImage,
        to url: URL,
        request: GenerationRequest,
        engine: any RasterEngine,
        timestamp: Date
    ) throws {
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
