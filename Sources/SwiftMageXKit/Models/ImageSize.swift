import Foundation

/// A coarse aspect-ratio descriptor for generation requests.
///
/// The exact pixel resolution the provider emits for each case is
/// provider- and model-dependent; see spec §6.1.
public enum ImageSize: String, Sendable, CaseIterable, Codable {
    /// 1:1 aspect ratio (default).
    case square
    /// Vertical aspect ratio (e.g. 9:16).
    case portrait
    /// Horizontal aspect ratio (e.g. 16:9).
    case landscape
}
