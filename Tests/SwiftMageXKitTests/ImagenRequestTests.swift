import XCTest
@testable import SwiftMageXKit

final class ImagenRequestTests: XCTestCase {
    // MARK: - Helpers

    private static let testPrompt = "a small red square on a white background"
    private static let testModel = "imagen-4.0-generate-001"
    private static let testAPIKey = "test-api-key-not-real"

    /// Wraps `imageBytes` in an Imagen-shaped `:predict` response with the
    /// given MIME, optionally producing multiple predictions for batch tests.
    private static func makeResponseJSON(
        imageBytes: Data,
        mimeType: String = "image/png",
        count: Int = 1
    ) throws -> Data {
        let prediction: [String: Any] = [
            "bytesBase64Encoded": imageBytes.base64EncodedString(),
            "mimeType": mimeType,
        ]
        let payload: [String: Any] = [
            "predictions": Array(repeating: prediction, count: count)
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private static let sampleImageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

    private static let instantSleeper: @Sendable (Duration) async throws -> Void = { _ in }

    private static func makeProvider(
        httpClient: any HTTPClient,
        apiKey: String = ImagenRequestTests.testAPIKey
    ) -> ImagenProvider {
        ImagenProvider(apiKey: apiKey, httpClient: httpClient, sleeper: instantSleeper)
    }

    private static func makeRequest(
        prompt: String = ImagenRequestTests.testPrompt,
        size: ImageSize = .square,
        count: Int = 1,
        model: String = ImagenRequestTests.testModel
    ) -> GenerationRequest {
        GenerationRequest(
            prompt: prompt,
            size: size,
            count: count,
            seed: nil,
            model: model
        )
    }

    // MARK: - Request assembly

    func testImagenRequestUsesPredictEndpoint() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        _ = try await provider.generate(Self.makeRequest())

        let recorded = try XCTUnwrap(mock.receivedRequests.first)
        XCTAssertEqual(
            recorded.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/\(Self.testModel):predict"
        )
        XCTAssertEqual(recorded.httpMethod, "POST")
        XCTAssertEqual(recorded.value(forHTTPHeaderField: "x-goog-api-key"), Self.testAPIKey)
        XCTAssertEqual(recorded.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testImagenRequestBodyShape() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        _ = try await provider.generate(Self.makeRequest(size: .landscape, count: 3))

        let recorded = try XCTUnwrap(mock.receivedRequests.first)
        let httpBody = try XCTUnwrap(recorded.httpBody)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
        )
        let instances = try XCTUnwrap(json["instances"] as? [[String: Any]])
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances.first?["prompt"] as? String, Self.testPrompt)

        let parameters = try XCTUnwrap(json["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["sampleCount"] as? Int, 3)
        XCTAssertEqual(parameters["aspectRatio"] as? String, "16:9")
    }

    func testImagenAspectRatioMapping() async throws {
        let cases: [(ImageSize, String)] = [
            (.square, "1:1"),
            (.portrait, "9:16"),
            (.landscape, "16:9"),
        ]
        for (size, expected) in cases {
            let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
            let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
            let provider = Self.makeProvider(httpClient: mock)

            _ = try await provider.generate(Self.makeRequest(size: size))

            let recorded = try XCTUnwrap(mock.receivedRequests.first)
            let httpBody = try XCTUnwrap(recorded.httpBody)
            let json = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
            )
            let parameters = try XCTUnwrap(json["parameters"] as? [String: Any])
            XCTAssertEqual(
                parameters["aspectRatio"] as? String,
                expected,
                "\(size) should map to \(expected)"
            )
        }
    }

    // MARK: - Response decoding

    func testImagenResponseDecodesAllPredictions() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes, count: 3)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        let images = try await provider.generate(Self.makeRequest(count: 3))

        XCTAssertEqual(images.count, 3, "all predictions should map to GeneratedImage entries")
        XCTAssertEqual(mock.receivedRequests.count, 1, "Imagen batches in a single :predict call")
        for image in images {
            XCTAssertEqual(image.data, Self.sampleImageBytes)
            XCTAssertEqual(image.format, .png)
            XCTAssertEqual(image.prompt, Self.testPrompt)
            XCTAssertEqual(image.model, Self.testModel)
        }
    }

    func testImagenResponseRejectsUnknownMimeType() async throws {
        let body = try Self.makeResponseJSON(
            imageBytes: Self.sampleImageBytes,
            mimeType: "image/heic"
        )
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        do {
            _ = try await provider.generate(Self.makeRequest())
            XCTFail("Expected unknown MIME type to throw")
        } catch let error as SwiftMageXError {
            guard case .provider(let message) = error else {
                return XCTFail("Expected .provider, got \(error)")
            }
            XCTAssertTrue(message.contains("heic"), "Message should mention MIME type, got: \(message)")
        }
    }

    func testImagenResponseRejectsEmptyPredictions() async throws {
        let body = try JSONSerialization.data(withJSONObject: ["predictions": []], options: [])
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        do {
            _ = try await provider.generate(Self.makeRequest())
            XCTFail("Expected empty predictions to throw")
        } catch let error as SwiftMageXError {
            guard case .provider = error else {
                return XCTFail("Expected .provider, got \(error)")
            }
        }
    }

    // MARK: - Retry policy

    func testImagenRetriesOn429UpToFiveTimes() async throws {
        let stubs = Array(
            repeating: MockHTTPClient.Stub(data: Data(), statusCode: 429),
            count: 6
        )
        let mock = MockHTTPClient(stubs: stubs)
        let provider = Self.makeProvider(httpClient: mock)

        do {
            _ = try await provider.generate(Self.makeRequest())
            XCTFail("Expected quota exhaustion to throw")
        } catch let error as SwiftMageXError {
            guard case .provider = error else {
                return XCTFail("Expected .provider, got \(error)")
            }
        }

        XCTAssertEqual(mock.receivedRequests.count, 6, "Should be 1 initial + 5 retries")
    }

    // MARK: - Validation

    func testImagenRejectsCountAboveBatchCap() async throws {
        let mock = MockHTTPClient()
        let provider = Self.makeProvider(httpClient: mock)

        do {
            _ = try await provider.generate(Self.makeRequest(count: 5))
            XCTFail("Expected count > 4 to throw .invalidInput")
        } catch let error as SwiftMageXError {
            guard case .invalidInput = error else {
                return XCTFail("Expected .invalidInput, got \(error)")
            }
        }

        XCTAssertEqual(mock.receivedRequests.count, 0)
    }

    func testImagenUltraRejectsCountAboveOneWithoutNetworkCall() async throws {
        let mock = MockHTTPClient()
        let provider = Self.makeProvider(httpClient: mock)

        do {
            _ = try await provider.generate(
                Self.makeRequest(count: 2, model: "imagen-4.0-ultra-generate-001")
            )
            XCTFail("Expected ultra count > 1 to throw .invalidInput")
        } catch let error as SwiftMageXError {
            guard case .invalidInput = error else {
                return XCTFail("Expected .invalidInput, got \(error)")
            }
        }

        XCTAssertEqual(mock.receivedRequests.count, 0, "ultra cap should be rejected before any network call")
    }

    func testImagenUltraAllowsSingleSample() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        let images = try await provider.generate(
            Self.makeRequest(count: 1, model: "imagen-4.0-ultra-generate-001")
        )

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(mock.receivedRequests.count, 1, "count == 1 should reach the provider")
    }
}
