import Foundation

/// The Google AI wire shape a model speaks.
///
/// Gemini-image models use `{model}:generateContent` with
/// `responseModalities: ["IMAGE"]`; Imagen models use `{model}:predict`
/// with `instances` and `parameters`. The two shapes share a host, an
/// auth header, and a retry policy but nothing else, so each family has
/// its own provider implementation.
public enum ImageModelFamily: String, Sendable, Equatable {
    case gemini
    case imagen
}

/// Static description of a known image-generation model.
public struct ImageModelDescriptor: Sendable, Equatable {
    public let id: String
    public let family: ImageModelFamily
    public let isPreview: Bool

    public init(id: String, family: ImageModelFamily, isPreview: Bool = false) {
        self.id = id
        self.family = family
        self.isPreview = isPreview
    }
}

/// Registry of built-in models the kit knows how to dispatch.
///
/// The orchestrator looks each `--model` value up here to decide which
/// provider to construct. Unknown IDs fall back to a prefix heuristic
/// so a freshly released Gemini or Imagen variant works without a code
/// change — but the entries listed below are what the CLI and MCP
/// surface to users.
///
/// **Only GA ids belong here.** A preview alias is retired some time after the
/// model reaches GA, and nothing in this file would notice: `--model` would keep
/// resolving through the prefix heuristic until Google switched the alias off,
/// and the failure would land on the user mid-command. Listing the GA id instead
/// means the catalog is wrong loudly, at review time, rather than quietly.
///
/// Refreshed 2026-09-22 against `ListModels` on a live key. What changed and why:
///
/// - The default moved off `gemini-2.5-flash-image`, which Google retires on
///   2026-10-02. Its documented replacement is `gemini-3.1-flash-image-preview`,
///   but that preview's own shutdown date (2026-06-25) has already passed, so the
///   GA `gemini-3.1-flash-image` is the honest target.
/// - `gemini-3-pro-image-preview` and `gemini-3.1-flash-image-preview` gave way to
///   their GA ids. Both aliases still resolved when this was written; neither is
///   advertised any more.
/// - The whole Imagen 4.0 family was retired on 2026-08-17 and now 404s on both
///   `v1` and `v1beta` — verified by `GET`, by `:predict`, and by its absence from
///   `ListModels`. Google's replacement for it is `gemini-3.1-flash-image`, the
///   default below. ``ImageModelFamily/imagen`` and ``ImagenProvider`` are kept on
///   purpose: Imagen still exists on Vertex AI, the `:predict` wire shape is
///   tested, and an `imagen-*` id passed by hand still routes to it and fails with
///   Google's own error rather than a confusing one of ours.
public enum ModelCatalog {
    public static let defaultModelID = "gemini-3.1-flash-image"

    public static let all: [ImageModelDescriptor] = [
        .init(id: "gemini-3.1-flash-image", family: .gemini),
        .init(id: "gemini-3.1-flash-lite-image", family: .gemini),
        .init(id: "gemini-3-pro-image", family: .gemini),
    ]

    /// Returns the descriptor for an exact match, or `nil` if unknown.
    public static func descriptor(for id: String) -> ImageModelDescriptor? {
        all.first { $0.id == id }
    }

    /// Resolves a model id to its wire family.
    ///
    /// Exact matches in ``all`` win. Otherwise we route by prefix so a
    /// new `imagen-*` or `gemini-*` build can be passed via `--model`
    /// without waiting for a catalog update.
    public static func family(for id: String) -> ImageModelFamily {
        if let descriptor = descriptor(for: id) { return descriptor.family }
        if id.hasPrefix("imagen-") { return .imagen }
        return .gemini
    }
}
