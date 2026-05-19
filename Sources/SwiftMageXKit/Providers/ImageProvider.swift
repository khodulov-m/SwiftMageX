import Foundation

/// A provider that turns text prompts into image bytes.
///
/// In MVP 0.1 there is exactly one implementation (`GeminiProvider`); the
/// protocol exists for testability against ``MockImageProvider`` and for the
/// 0.2 expansion to local providers.
public protocol ImageProvider: Sendable {
    /// A stable identifier for the provider — used in logs and metadata.
    var id: String { get }

    /// Static capabilities, surfaced so callers can validate a request before
    /// hitting the network.
    var capabilities: ProviderCapabilities { get }

    /// Generate one or more images for `request`.
    ///
    /// Implementations are responsible for honoring `request.count`, applying
    /// any provider-specific retry/backoff policy, and decoding the response
    /// into ``GeneratedImage`` values.
    func generate(_ request: GenerationRequest) async throws -> [GeneratedImage]
}

/// Static description of what an ``ImageProvider`` supports.
public struct ProviderCapabilities: Sendable, Equatable {
    /// Whether the provider passes the seed through to its model.
    /// If `false`, callers should still record the seed in output metadata.
    public var supportsSeed: Bool

    /// The maximum value of `count` the provider will accept in one call.
    public var maxBatchSize: Int

    /// The aspect ratios the provider supports.
    public var supportedSizes: [ImageSize]

    /// Creates a capabilities descriptor.
    public init(
        supportsSeed: Bool,
        maxBatchSize: Int,
        supportedSizes: [ImageSize]
    ) {
        self.supportsSeed = supportsSeed
        self.maxBatchSize = maxBatchSize
        self.supportedSizes = supportedSizes
    }
}
