import Foundation

/// A fully-resolved request for image generation.
///
/// Frontends build a `GenerationRequest` after parsing and validating their
/// inputs and pass it to an ``ImageProvider``. Sendable because it crosses an
/// async boundary into the provider.
public struct GenerationRequest: Sendable, Equatable {
    /// The text prompt describing what to generate.
    public var prompt: String
    /// Desired aspect ratio.
    public var size: ImageSize
    /// Number of variants to request — capped at 4 per spec §6.1.
    public var count: Int
    /// Optional reproducibility seed. Support is provider-dependent; see spec §12.
    public var seed: UInt64?
    /// Provider-specific model identifier (e.g. `gemini-2.5-flash-image`).
    public var model: String

    /// Creates a generation request.
    public init(
        prompt: String,
        size: ImageSize,
        count: Int,
        seed: UInt64?,
        model: String
    ) {
        self.prompt = prompt
        self.size = size
        self.count = count
        self.seed = seed
        self.model = model
    }
}
