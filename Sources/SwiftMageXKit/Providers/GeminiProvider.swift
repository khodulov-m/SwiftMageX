import Foundation

/// The Gemini implementation of ``ImageProvider``.
///
/// Calls `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
/// with an `x-goog-api-key` header, decoding base64 image bytes from the
/// `candidates[].content.parts[].inlineData` field. See spec §8.
public struct GeminiProvider: ImageProvider {
    public let id: String = "gemini"

    public let capabilities: ProviderCapabilities

    private let apiKey: String
    private let httpClient: any HTTPClient

    /// Creates a Gemini provider.
    ///
    /// - Parameters:
    ///   - apiKey: The Gemini API key. Read by frontends from the environment.
    ///   - httpClient: The HTTP client used to perform requests. Injected to
    ///     keep the type testable against ``MockHTTPClient``.
    public init(apiKey: String, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.httpClient = httpClient
        // Seed support for `gemini-2.5-flash-image` must be verified during
        // milestone 4 (spec §17). Until then, advertise unsupported and rely
        // on metadata to preserve the recorded intent.
        self.capabilities = ProviderCapabilities(
            supportsSeed: false,
            maxBatchSize: 4,
            supportedSizes: ImageSize.allCases
        )
    }

    public func generate(_ request: GenerationRequest) async throws -> [GeneratedImage] {
        // TODO(milestone 4): implement HTTP request assembly, retry/backoff on
        // 429 per spec §13, base64 decode of inlineData, and mapping into
        // [GeneratedImage]. Until then this is intentionally a hard stub.
        _ = apiKey
        _ = httpClient
        _ = request
        throw SwiftMageXError.provider("GeminiProvider.generate is not implemented yet (milestone 4)")
    }
}
