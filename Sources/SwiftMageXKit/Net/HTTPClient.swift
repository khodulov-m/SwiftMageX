import Foundation

/// A minimal HTTP-client abstraction over `URLSession` so provider logic can
/// be exercised against ``MockHTTPClient`` without real network traffic.
///
/// The shape mirrors the most common `URLSession` async call so the default
/// implementation in ``URLSessionHTTPClient`` stays trivial.
public protocol HTTPClient: Sendable {
    /// Perform `request` and return the response body and HTTP metadata.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
