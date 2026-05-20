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
    private let sleeper: @Sendable (Duration) async throws -> Void

    private static let endpointScheme = "https"
    private static let endpointHost = "generativelanguage.googleapis.com"
    private static let endpointBasePath = "/v1beta/models"
    private static let maxRetries = 5

    /// Creates a Gemini provider.
    ///
    /// - Parameters:
    ///   - apiKey: The Gemini API key. Read by frontends from the environment.
    ///   - httpClient: The HTTP client used to perform requests. Injected to
    ///     keep the type testable against ``MockHTTPClient``.
    public init(apiKey: String, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.init(apiKey: apiKey, httpClient: httpClient, sleeper: { duration in
            try await Task.sleep(for: duration)
        })
    }

    // Spec §17 leaves seed support for `gemini-2.5-flash-image` unconfirmed;
    // until that is verified by a live call, advertise it as unsupported and
    // rely on metadata (milestone 5) to preserve the recorded intent.
    init(
        apiKey: String,
        httpClient: any HTTPClient,
        sleeper: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.apiKey = apiKey
        self.httpClient = httpClient
        self.sleeper = sleeper
        self.capabilities = ProviderCapabilities(
            supportsSeed: false,
            maxBatchSize: 4,
            supportedSizes: ImageSize.allCases
        )
    }

    public func generate(_ request: GenerationRequest) async throws -> [GeneratedImage] {
        guard request.count >= 1 else {
            throw SwiftMageXError.invalidInput("count must be >= 1 (got \(request.count))")
        }
        guard request.count <= capabilities.maxBatchSize else {
            throw SwiftMageXError.invalidInput(
                "count must be <= \(capabilities.maxBatchSize) (got \(request.count))"
            )
        }

        if request.count == 1 {
            return [try await performOne(request)]
        }

        return try await withThrowingTaskGroup(of: (Int, GeneratedImage).self) { group in
            for index in 0..<request.count {
                group.addTask {
                    let image = try await self.performOne(request)
                    return (index, image)
                }
            }
            var results: [(Int, GeneratedImage)] = []
            results.reserveCapacity(request.count)
            for try await pair in group {
                results.append(pair)
            }
            results.sort { $0.0 < $1.0 }
            return results.map(\.1)
        }
    }

    private func performOne(_ request: GenerationRequest) async throws -> GeneratedImage {
        let urlRequest = try buildURLRequest(for: request)
        let (data, response) = try await sendWithRetry(urlRequest)
        return try decodeResponse(data, statusCode: response.statusCode, request: request)
    }

    private func buildURLRequest(for request: GenerationRequest) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = Self.endpointScheme
        components.host = Self.endpointHost
        components.path = "\(Self.endpointBasePath)/\(request.model):generateContent"
        guard let url = components.url else {
            throw SwiftMageXError.invalidInput(
                "Could not build endpoint URL for model \(request.model)"
            )
        }

        let body = GeminiRequestBody(
            contents: [
                GeminiRequestContent(
                    role: "user",
                    parts: [GeminiRequestPart(text: request.prompt)]
                )
            ],
            generationConfig: GeminiGenerationConfig(responseModalities: ["IMAGE"])
        )
        let payload: Data
        do {
            payload = try JSONEncoder().encode(body)
        } catch {
            throw SwiftMageXError.provider(
                "Failed to encode Gemini request body: \(error.localizedDescription)"
            )
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = payload
        return urlRequest
    }

    private func sendWithRetry(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let (data, response) = try await httpClient.send(urlRequest)
            if response.statusCode != 429 {
                return (data, response)
            }
            if attempt >= Self.maxRetries {
                throw SwiftMageXError.provider(
                    "quota exhausted after \(Self.maxRetries) retries"
                )
            }
            let backoff = Duration.seconds(1 << attempt)
            attempt += 1
            try await sleeper(backoff)
        }
    }

    private func decodeResponse(
        _ data: Data,
        statusCode: Int,
        request: GenerationRequest
    ) throws -> GeneratedImage {
        guard (200..<300).contains(statusCode) else {
            let snippet = String(data: data.prefix(512), encoding: .utf8)
                ?? "<\(data.count) bytes of non-UTF8 body>"
            throw SwiftMageXError.provider("Gemini returned HTTP \(statusCode): \(snippet)")
        }

        let decoded: GeminiResponse
        do {
            decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw SwiftMageXError.provider(
                "Failed to decode Gemini response: \(error.localizedDescription)"
            )
        }

        let inline = decoded.candidates?
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.inlineData)
            .first
        guard let inline else {
            throw SwiftMageXError.provider("Gemini response contained no image inlineData")
        }

        let format = try mapMimeType(inline.mimeType)
        guard let bytes = Data(base64Encoded: inline.data) else {
            throw SwiftMageXError.provider("Gemini inlineData was not valid base64")
        }

        return GeneratedImage(
            data: bytes,
            format: format,
            prompt: request.prompt,
            model: request.model,
            seed: capabilities.supportsSeed ? request.seed : nil
        )
    }

    private func mapMimeType(_ mime: String) throws -> ImageFormat {
        switch mime.lowercased() {
        case ImageFormat.png.mimeType:
            return .png
        case ImageFormat.jpeg.mimeType, "image/jpg":
            return .jpeg
        default:
            throw SwiftMageXError.provider("Unsupported Gemini image MIME type: \(mime)")
        }
    }
}

// MARK: - Wire types (kept private to localize Gemini API changes)

private struct GeminiRequestBody: Encodable {
    let contents: [GeminiRequestContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiRequestContent: Encodable {
    let role: String
    let parts: [GeminiRequestPart]
}

private struct GeminiRequestPart: Encodable {
    let text: String
}

private struct GeminiGenerationConfig: Encodable {
    let responseModalities: [String]
}

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]?
}

private struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent?
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]?
}

private struct GeminiResponsePart: Decodable {
    let inlineData: GeminiInlineData?
}

private struct GeminiInlineData: Decodable {
    let mimeType: String
    let data: String
}
