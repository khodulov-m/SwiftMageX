import Foundation

/// An image attached to a ``GenerationRequest`` as a reference for editing or
/// composition. Carries its bytes alongside its MIME type so providers don't
/// have to re-detect the format.
public struct ReferenceImage: Sendable, Equatable {
    /// Raw encoded image bytes (PNG or JPEG).
    public var data: Data
    /// MIME type — `image/png` or `image/jpeg`.
    public var mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// A fully-resolved request for image generation.
///
/// Frontends build a `GenerationRequest` after parsing and validating their
/// inputs and pass it to an ``ImageProvider``. Sendable because it crosses an
/// async boundary into the provider.
///
/// A non-empty ``referenceImages`` array turns the same shape into an
/// image-to-image / multi-image edit request. Gemini's `:generateContent`
/// accepts N inline image parts alongside the text prompt — one for each
/// reference, plus an optional mask. Imagen's `:predict` does not accept
/// image inputs at all, so the Imagen provider rejects any request that
/// carries references or a mask.
public struct GenerationRequest: Sendable, Equatable {
    /// The text prompt describing what to generate (or what edit to apply).
    public var prompt: String
    /// Coarse aspect-ratio preset, kept for Imagen, whose `:predict` always
    /// needs a ratio and falls back to this one when ``aspectRatio`` is `nil`.
    /// Gemini ignores it — frontends map an explicit `--size` into
    /// ``aspectRatio`` instead.
    public var size: ImageSize
    /// Exact output ratio sent to Gemini. `nil` sends none: the model picks
    /// its own framing for text-to-image and keeps the primary reference's
    /// proportions for an edit.
    public var aspectRatio: AspectRatio?
    /// Output resolution tier. `nil` leaves it to the model (1K today).
    public var resolution: ImageResolution?
    /// Number of variants to request — capped at 4 per spec §6.1.
    public var count: Int
    /// Optional reproducibility seed. Support is provider-dependent; see spec §12.
    public var seed: UInt64?
    /// Provider-specific model identifier (e.g. `gemini-3.1-flash-image`).
    public var model: String
    /// Reference images for image-to-image / multi-image edit. Empty means a
    /// pure text-to-image request. The first entry is treated as the primary
    /// source; later entries are additional references the prompt can compose
    /// against ("take the subject from image 1 and put it in scene 2").
    /// Setting this on a non-Gemini provider surfaces
    /// ``SwiftMageXError/invalidInput(_:)``.
    public var referenceImages: [ReferenceImage]
    /// Optional mask bytes. White marks the region to edit; black preserves
    /// the original. Applied against the *primary* reference image. Only
    /// meaningful when ``referenceImages`` is non-empty.
    public var mask: Data?
    /// MIME type of ``mask``. Must be `image/png` or `image/jpeg`.
    public var maskMimeType: String?

    /// Creates a generation request. Image fields default to empty / nil so
    /// existing text-to-image call sites continue to compile unchanged.
    public init(
        prompt: String,
        size: ImageSize,
        count: Int,
        seed: UInt64?,
        model: String,
        referenceImages: [ReferenceImage] = [],
        mask: Data? = nil,
        maskMimeType: String? = nil,
        aspectRatio: AspectRatio? = nil,
        resolution: ImageResolution? = nil
    ) {
        self.prompt = prompt
        self.size = size
        self.count = count
        self.seed = seed
        self.model = model
        self.referenceImages = referenceImages
        self.mask = mask
        self.maskMimeType = maskMimeType
        self.aspectRatio = aspectRatio
        self.resolution = resolution
    }
}
