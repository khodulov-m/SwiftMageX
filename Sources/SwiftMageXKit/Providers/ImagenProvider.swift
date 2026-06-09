import Foundation

/// The Imagen implementation of ``ImageProvider``.
///
/// Calls `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:predict`
/// with an `x-goog-api-key` header, decoding base64 image bytes from the
/// `predictions[].bytesBase64Encoded` field.
///
/// Differences from ``GeminiProvider`` worth knowing about:
/// 1. Endpoint suffix is `:predict`, not `:generateContent`.
/// 2. Multi-image batches are a single call (`parameters.sampleCount`),
///    not N parallel calls. `imagen-*-ultra-*` caps `sampleCount` at 1
///    server-side — overrun surfaces as HTTP 400 from the API.
/// 3. Aspect ratio is explicit in `parameters.aspectRatio`.
public struct ImagenProvider: ImageProvider {
    public let id: String = "imagen"

    public let capabilities: ProviderCapabilities

    private let apiKey: String
    private let httpClient: any HTTPClient
    private let sleeper: @Sendable (Duration) async throws -> Void

    private static let endpointScheme = "https"
    private static let endpointHost = "generativelanguage.googleapis.com"
    private static let endpointBasePath = "/v1beta/models"
    private static let maxRetries = 5

    public init(apiKey: String, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.init(apiKey: apiKey, httpClient: httpClient, sleeper: { duration in
            try await Task.sleep(for: duration)
        })
    }

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
        // Imagen's `:predict` shape has no inline-image slot. The CLI gates
        // on this at validate(); the guard here catches anything that slipped
        // past — e.g. a future MCP caller forgetting to check the family.
        guard request.referenceImages.isEmpty, request.mask == nil else {
            throw SwiftMageXError.invalidInput(
                "Imagen models do not support image-to-image edit; use a gemini-* model"
            )
        }
        // Ultra variants accept only a single sample per `:predict` call. Reject
        // a multi-sample request up front (exit code 2) instead of paying a
        // network round-trip for a server-side HTTP 400.
        guard !(Self.isUltra(request.model) && request.count > 1) else {
            throw SwiftMageXError.invalidInput(
                "\(request.model) supports only a single image per request (got count \(request.count)); use --count 1"
            )
        }

        let urlRequest = try buildURLRequest(for: request)
        let (data, response) = try await sendWithRetry(urlRequest)
        return try decodeResponse(data, statusCode: response.statusCode, request: request)
    }

    private func buildURLRequest(for request: GenerationRequest) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = Self.endpointScheme
        components.host = Self.endpointHost
        components.path = "\(Self.endpointBasePath)/\(request.model):predict"
        guard let url = components.url else {
            throw SwiftMageXError.invalidInput(
                "Could not build endpoint URL for model \(request.model)"
            )
        }

        let body = ImagenRequestBody(
            instances: [ImagenInstance(prompt: request.prompt)],
            parameters: ImagenParameters(
                sampleCount: request.count,
                aspectRatio: Self.aspectRatio(for: request.size)
            )
        )
        let payload: Data
        do {
            payload = try JSONEncoder().encode(body)
        } catch {
            throw SwiftMageXError.provider(
                "Failed to encode Imagen request body: \(error.localizedDescription)"
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
    ) throws -> [GeneratedImage] {
        guard (200..<300).contains(statusCode) else {
            let snippet = String(data: data.prefix(512), encoding: .utf8)
                ?? "<\(data.count) bytes of non-UTF8 body>"
            throw SwiftMageXError.provider("Imagen returned HTTP \(statusCode): \(snippet)")
        }

        let decoded: ImagenResponse
        do {
            decoded = try JSONDecoder().decode(ImagenResponse.self, from: data)
        } catch {
            throw SwiftMageXError.provider(
                "Failed to decode Imagen response: \(error.localizedDescription)"
            )
        }

        let predictions = decoded.predictions ?? []
        guard !predictions.isEmpty else {
            throw SwiftMageXError.provider("Imagen response contained no predictions")
        }

        return try predictions.map { prediction in
            let format = try mapMimeType(prediction.mimeType ?? ImageFormat.png.mimeType)
            guard let bytes = Data(base64Encoded: prediction.bytesBase64Encoded) else {
                throw SwiftMageXError.provider("Imagen bytesBase64Encoded was not valid base64")
            }
            return GeneratedImage(
                data: bytes,
                format: format,
                prompt: request.prompt,
                model: request.model,
                seed: capabilities.supportsSeed ? request.seed : nil
            )
        }
    }

    private func mapMimeType(_ mime: String) throws -> ImageFormat {
        switch mime.lowercased() {
        case ImageFormat.png.mimeType:
            return .png
        case ImageFormat.jpeg.mimeType, "image/jpg":
            return .jpeg
        default:
            throw SwiftMageXError.provider("Unsupported Imagen image MIME type: \(mime)")
        }
    }

    /// Whether `model` is an Imagen *ultra* variant, which the API caps at a
    /// single sample per `:predict` call. Matched by substring so a future
    /// `imagen-*-ultra-*` build is covered without a catalog change, mirroring
    /// the prefix routing in ``ModelCatalog``.
    private static func isUltra(_ model: String) -> Bool {
        model.lowercased().contains("ultra")
    }

    private static func aspectRatio(for size: ImageSize) -> String {
        switch size {
        case .square: return "1:1"
        case .portrait: return "9:16"
        case .landscape: return "16:9"
        }
    }
}

// MARK: - Wire types (kept private to localize Imagen API changes)

private struct ImagenRequestBody: Encodable {
    let instances: [ImagenInstance]
    let parameters: ImagenParameters
}

private struct ImagenInstance: Encodable {
    let prompt: String
}

private struct ImagenParameters: Encodable {
    let sampleCount: Int
    let aspectRatio: String
}

private struct ImagenResponse: Decodable {
    let predictions: [ImagenPrediction]?
}

private struct ImagenPrediction: Decodable {
    let bytesBase64Encoded: String
    let mimeType: String?
}
