import Foundation

/// A fully-resolved request for image generation.
///
/// Frontends build a `GenerationRequest` after parsing and validating their
/// inputs and pass it to an ``ImageProvider``. Sendable because it crosses an
/// async boundary into the provider.
///
/// The optional `referenceImage` / `mask` fields turn the same shape into an
/// image-to-image edit request. Gemini's `:generateContent` accepts inline
/// image parts alongside the text prompt; Imagen's `:predict` does not, so
/// the Imagen provider rejects requests that carry image bytes.
public struct GenerationRequest: Sendable, Equatable {
    /// The text prompt describing what to generate (or what edit to apply).
    public var prompt: String
    /// Desired aspect ratio. Ignored for edit requests — the output dimensions
    /// follow the input image.
    public var size: ImageSize
    /// Number of variants to request — capped at 4 per spec §6.1.
    public var count: Int
    /// Optional reproducibility seed. Support is provider-dependent; see spec §12.
    public var seed: UInt64?
    /// Provider-specific model identifier (e.g. `gemini-2.5-flash-image`).
    public var model: String
    /// Optional source image bytes for image-to-image / inpainting. When set,
    /// the request routes through Gemini's edit path; setting this on a
    /// non-Gemini provider surfaces ``SwiftMageXError/invalidInput(_:)``.
    public var referenceImage: Data?
    /// MIME type of ``referenceImage``. Must be `image/png` or `image/jpeg`.
    public var referenceImageMimeType: String?
    /// Optional mask image bytes. White marks the region to edit; black
    /// preserves the original. Only meaningful when ``referenceImage`` is set.
    public var mask: Data?
    /// MIME type of ``mask``. Must be `image/png` or `image/jpeg`.
    public var maskMimeType: String?

    /// Creates a generation request. Image fields default to `nil` so existing
    /// text-to-image call sites continue to compile unchanged.
    public init(
        prompt: String,
        size: ImageSize,
        count: Int,
        seed: UInt64?,
        model: String,
        referenceImage: Data? = nil,
        referenceImageMimeType: String? = nil,
        mask: Data? = nil,
        maskMimeType: String? = nil
    ) {
        self.prompt = prompt
        self.size = size
        self.count = count
        self.seed = seed
        self.model = model
        self.referenceImage = referenceImage
        self.referenceImageMimeType = referenceImageMimeType
        self.mask = mask
        self.maskMimeType = maskMimeType
    }
}
