import XCTest
@testable import SwiftMageXKit

final class GeminiRequestTests: XCTestCase {
    /// Placeholder — milestone 4 replaces this with assertions on the
    /// constructed `URLRequest`: endpoint URL, `x-goog-api-key` header,
    /// and the JSON body shape per spec §8.
    func testStubProviderThrowsNotImplemented() async {
        // TODO(milestone 4): swap in a real Gemini request-assembly test using
        // MockHTTPClient — verify endpoint, headers, body, and 429 retry policy.
        let provider = GeminiProvider(apiKey: "fake", httpClient: MockHTTPClient())
        let request = GenerationRequest(
            prompt: "anything",
            size: .square,
            count: 1,
            seed: nil,
            model: "gemini-2.5-flash-image"
        )

        do {
            _ = try await provider.generate(request)
            XCTFail("Expected the stub to throw")
        } catch let error as SwiftMageXError {
            guard case .provider = error else {
                return XCTFail("Expected .provider, got \(error)")
            }
        } catch {
            XCTFail("Expected SwiftMageXError, got \(error)")
        }
    }

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
