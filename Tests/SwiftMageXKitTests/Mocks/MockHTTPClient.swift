import Foundation
import os
@testable import SwiftMageXKit

/// Test double for ``HTTPClient``. Returns scripted responses and records the
/// requests it received so tests can verify Gemini request assembly without
/// hitting the network.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    /// A canned response, applied to the next call in FIFO order.
    struct Stub {
        let data: Data
        let statusCode: Int
        let headers: [String: String]

        init(data: Data = Data(), statusCode: Int = 200, headers: [String: String] = [:]) {
            self.data = data
            self.statusCode = statusCode
            self.headers = headers
        }
    }

    private struct State {
        var stubs: [Stub]
        var receivedRequests: [URLRequest] = []
    }

    private let state: OSAllocatedUnfairLock<State>
    private let fallbackError: Error?

    /// All requests seen by this mock, in order.
    var receivedRequests: [URLRequest] {
        state.withLock { $0.receivedRequests }
    }

    /// Creates a mock with a queue of stubbed responses.
    init(stubs: [Stub] = [], fallbackError: Error? = nil) {
        self.state = OSAllocatedUnfairLock(initialState: State(stubs: stubs))
        self.fallbackError = fallbackError
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let stub: Stub? = state.withLock { state in
            state.receivedRequests.append(request)
            return state.stubs.isEmpty ? nil : state.stubs.removeFirst()
        }

        if let stub {
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mock.invalid")!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            return (stub.data, response)
        }
        if let fallbackError {
            throw fallbackError
        }
        throw SwiftMageXError.provider("MockHTTPClient: no stubbed response and no fallback error")
    }
}
