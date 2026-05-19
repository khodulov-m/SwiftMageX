import Foundation

/// A pixel-format / container identifier used when reading or writing images.
public enum ImageFormat: String, Sendable, CaseIterable, Codable {
    /// Portable Network Graphics — lossless.
    case png
    /// JPEG — lossy, quality-controlled.
    case jpeg

    /// The canonical filename extension (without the leading dot).
    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    /// The MIME type used by HTTP / MCP image content.
    public var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .jpeg: return "image/jpeg"
        }
    }
}
