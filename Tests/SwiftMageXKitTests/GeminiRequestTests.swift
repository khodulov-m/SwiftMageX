import XCTest
@testable import SwiftMageXKit

final class GeminiRequestTests: XCTestCase {
    // MARK: - Helpers

    private static let testPrompt = "a small red square on a white background"
    private static let testModel = "gemini-2.5-flash-image"
    private static let testAPIKey = "test-api-key-not-real"

    /// Wraps `imageBytes` in a Gemini-shaped JSON response with the given MIME.
    private static func makeResponseJSON(
        imageBytes: Data,
        mimeType: String = "image/png"
    ) throws -> Data {
        let payload: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            [
                                "inlineData": [
                                    "mimeType": mimeType,
                                    "data": imageBytes.base64EncodedString()
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    /// A tiny "image" payload — the tests assert byte round-tripping, not
    /// PNG validity, so arbitrary bytes are fine.
    private static let sampleImageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

    /// A no-op sleeper so 429 retry tests don't actually wait.
    private static let instantSleeper: @Sendable (Duration) async throws -> Void = { _ in }

    private static func makeProvider(
        httpClient: any HTTPClient,
        apiKey: String = GeminiRequestTests.testAPIKey
    ) -> GeminiProvider {
        GeminiProvider(apiKey: apiKey, httpClient: httpClient, sleeper: instantSleeper)
    }

    private static func makeRequest(
        prompt: String = GeminiRequestTests.testPrompt,
        count: Int = 1,
        model: String = GeminiRequestTests.testModel
    ) -> GenerationRequest {
        GenerationRequest(
            prompt: prompt,
            size: .square,
            count: count,
            seed: nil,
            model: model
        )
    }

    // MARK: - Request assembly

    func testGeminiRequestUsesCorrectEndpoint() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        _ = try await provider.generate(Self.makeRequest())

        let recorded = try XCTUnwrap(mock.receivedRequests.first)
        XCTAssertEqual(
            recorded.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/\(Self.testModel):generateContent"
        )
        XCTAssertEqual(recorded.httpMethod, "POST")
    }

    func testGeminiRequestSetsAPIKeyHeader() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        _ = try await provider.generate(Self.makeRequest())

        let recorded = try XCTUnwrap(mock.receivedRequests.first)
        XCTAssertEqual(recorded.value(forHTTPHeaderField: "x-goog-api-key"), Self.testAPIKey)
        XCTAssertEqual(recorded.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testGeminiRequestBodyIncludesPrompt() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        _ = try await provider.generate(Self.makeRequest())

        let recorded = try XCTUnwrap(mock.receivedRequests.first)
        let httpBody = try XCTUnwrap(recorded.httpBody)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
        )
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        let firstContent = try XCTUnwrap(contents.first)
        XCTAssertEqual(firstContent["role"] as? String, "user")
        let parts = try XCTUnwrap(firstContent["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 1, "Text-only request should have exactly one part")
        XCTAssertEqual(parts.first?["text"] as? String, Self.testPrompt)
        XCTAssertNil(parts.first?["inlineData"], "Text part must not carry an inlineData key")

        let generationConfig = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["responseModalities"] as? [String], ["IMAGE"])
    }

    // MARK: - Edit request assembly

    func testGeminiEditRequestIncludesInlineDataPart() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        let inputBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
        let request = GenerationRequest(
            prompt: Self.testPrompt,
            size: .square,
            count: 1,
            seed: nil,
            model: Self.testModel,
            referenceImage: inputBytes,
            referenceImageMimeType: "image/png"
        )

        _ = try await provider.generate(request)

        let recorded = try XCTUnwrap(mock.receivedRequests.first)
        let httpBody = try XCTUnwrap(recorded.httpBody)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
        )
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2, "Edit request should have text + image parts")

        XCTAssertEqual(parts[0]["text"] as? String, Self.testPrompt)
        XCTAssertNil(parts[0]["inlineData"], "Sum-type encoding must not emit null inlineData")

        let inlineData = try XCTUnwrap(parts[1]["inlineData"] as? [String: Any])
        XCTAssertNil(parts[1]["text"], "Sum-type encoding must not emit null text")
        XCTAssertEqual(inlineData["mimeType"] as? String, "image/png")
        let encoded = try XCTUnwrap(inlineData["data"] as? String)
        XCTAssertEqual(Data(base64Encoded: encoded), inputBytes)
    }

    func testGeminiEditRequestIncludesMaskPart() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        let inputBytes = Data([0xAA, 0xBB, 0xCC])
        let maskBytes = Data([0x11, 0x22, 0x33, 0x44])
        let request = GenerationRequest(
            prompt: Self.testPrompt,
            size: .square,
            count: 1,
            seed: nil,
            model: Self.testModel,
            referenceImage: inputBytes,
            referenceImageMimeType: "image/png",
            mask: maskBytes,
            maskMimeType: "image/jpeg"
        )

        _ = try await provider.generate(request)

        let recorded = try XCTUnwrap(mock.receivedRequests.first)
        let httpBody = try XCTUnwrap(recorded.httpBody)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
        )
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 3, "Edit request with mask should have text + image + mask parts")

        let imagePart = try XCTUnwrap(parts[1]["inlineData"] as? [String: Any])
        XCTAssertEqual(imagePart["mimeType"] as? String, "image/png")
        XCTAssertEqual(Data(base64Encoded: imagePart["data"] as? String ?? ""), inputBytes)

        let maskPart = try XCTUnwrap(parts[2]["inlineData"] as? [String: Any])
        XCTAssertEqual(maskPart["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(Data(base64Encoded: maskPart["data"] as? String ?? ""), maskBytes)
    }

    // MARK: - Response decoding

    func testGeminiResponseDecodesBase64Image() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [.init(data: body, statusCode: 200)])
        let provider = Self.makeProvider(httpClient: mock)

        let images = try await provider.generate(Self.makeRequest())

        XCTAssertEqual(images.count, 1)
        let image = try XCTUnwrap(images.first)
        XCTAssertEqual(image.data, Self.sampleImageBytes)
        XCTAssertEqual(image.format, .png)
        XCTAssertEqual(image.prompt, Self.testPrompt)
        XCTAssertEqual(image.model, Self.testModel)
    }

    func testGeminiResponseRejectsUnknownMimeType() async throws {
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

    // MARK: - Retry policy

    func testGeminiRetriesOn429UpToFiveTimes() async throws {
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

    func testGeminiRetryRecoversWhenLaterAttemptSucceeds() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [
            .init(data: Data(), statusCode: 429),
            .init(data: Data(), statusCode: 429),
            .init(data: body, statusCode: 200)
        ])
        let provider = Self.makeProvider(httpClient: mock)

        let images = try await provider.generate(Self.makeRequest())

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(mock.receivedRequests.count, 3)
    }

    func testGeminiDoesNotRetryOn400() async throws {
        let mock = MockHTTPClient(stubs: [
            .init(data: Data("bad request".utf8), statusCode: 400)
        ])
        let provider = Self.makeProvider(httpClient: mock)

        do {
            _ = try await provider.generate(Self.makeRequest())
            XCTFail("Expected 400 to throw")
        } catch let error as SwiftMageXError {
            guard case .provider = error else {
                return XCTFail("Expected .provider, got \(error)")
            }
        }

        XCTAssertEqual(mock.receivedRequests.count, 1, "400 must be terminal — no retries")
    }

    // MARK: - Fan-out

    func testGeminiFansOutForCountGreaterThanOne() async throws {
        let body = try Self.makeResponseJSON(imageBytes: Self.sampleImageBytes)
        let mock = MockHTTPClient(stubs: [
            .init(data: body, statusCode: 200),
            .init(data: body, statusCode: 200),
            .init(data: body, statusCode: 200)
        ])
        let provider = Self.makeProvider(httpClient: mock)

        let images = try await provider.generate(Self.makeRequest(count: 3))

        XCTAssertEqual(images.count, 3)
        XCTAssertEqual(mock.receivedRequests.count, 3)
    }

    func testGeminiRejectsCountAboveBatchCap() async throws {
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

    // MARK: - Mock-provider sanity (preserved from milestone 1)

    func testMockProviderRecordsRequests() async throws {
        let mock = MockImageProvider(images: [])
        let request = GenerationRequest(
            prompt: "hello",
            size: .portrait,
            count: 2,
            seed: 42,
            model: "gemini-2.5-flash-image"
        )

        _ = try await mock.generate(request)

        XCTAssertEqual(mock.receivedRequests.count, 1)
        XCTAssertEqual(mock.receivedRequests.first, request)
    }
}
