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
public enum ModelCatalog {
    public static let defaultModelID = "gemini-2.5-flash-image"

    public static let all: [ImageModelDescriptor] = [
        .init(id: "gemini-2.5-flash-image", family: .gemini),
        .init(id: "gemini-3-pro-image-preview", family: .gemini, isPreview: true),
        .init(id: "gemini-3.1-flash-image-preview", family: .gemini, isPreview: true),
        .init(id: "imagen-4.0-generate-001", family: .imagen),
        .init(id: "imagen-4.0-fast-generate-001", family: .imagen),
        .init(id: "imagen-4.0-ultra-generate-001", family: .imagen),
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
