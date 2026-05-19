import Foundation

/// A single image returned by an ``ImageProvider``, prior to being written to disk.
public struct GeneratedImage: Sendable, Equatable {
    /// Raw encoded image bytes in the provider's chosen ``format``.
    public var data: Data
    /// The container format of ``data``.
    public var format: ImageFormat
    /// The prompt that produced this image — embedded into output metadata.
    public var prompt: String
    /// The provider-specific model identifier used to generate the image.
    public var model: String
    /// The seed if one was supplied and accepted; otherwise nil.
    public var seed: UInt64?

    /// Creates a generated-image envelope.
    public init(
        data: Data,
        format: ImageFormat,
        prompt: String,
        model: String,
        seed: UInt64?
    ) {
        self.data = data
        self.format = format
        self.prompt = prompt
        self.model = model
        self.seed = seed
    }
}
