import Foundation
import os
@testable import SwiftMageXKit

/// Test double for ``ImageProvider``. Returns a canned set of images and
/// records the request it received so tests can make assertions on it.
final class MockImageProvider: ImageProvider, @unchecked Sendable {
    let id: String = "mock"
    let capabilities: ProviderCapabilities

    private let received: OSAllocatedUnfairLock<[GenerationRequest]>
    private let result: Result<[GeneratedImage], SwiftMageXError>

    /// All `generate` requests this mock has seen, in order.
    var receivedRequests: [GenerationRequest] {
        received.withLock { $0 }
    }

    /// Creates a mock that always returns `images`.
    init(
        capabilities: ProviderCapabilities = .init(
            supportsSeed: true,
            maxBatchSize: 4,
            supportedSizes: ImageSize.allCases
        ),
        images: [GeneratedImage] = []
    ) {
        self.capabilities = capabilities
        self.received = OSAllocatedUnfairLock(initialState: [])
        self.result = .success(images)
    }

    /// Creates a mock that always throws `error`.
    init(capabilities: ProviderCapabilities, throwing error: SwiftMageXError) {
        self.capabilities = capabilities
        self.received = OSAllocatedUnfairLock(initialState: [])
        self.result = .failure(error)
    }

    func generate(_ request: GenerationRequest) async throws -> [GeneratedImage] {
        received.withLock { $0.append(request) }
        return try result.get()
    }
}
