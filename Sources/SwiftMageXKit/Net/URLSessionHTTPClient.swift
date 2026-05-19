import Foundation

/// The production ``HTTPClient`` — a thin wrapper over `URLSession`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    /// Creates a client backed by `session` (default: `.shared`).
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SwiftMageXError.provider("Non-HTTP response received from \(request.url?.absoluteString ?? "<unknown>")")
        }
        return (data, http)
    }
}
