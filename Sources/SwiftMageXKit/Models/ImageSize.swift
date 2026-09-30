import Foundation

/// A coarse aspect-ratio preset for generation requests.
///
/// Each case stands for an exact ``AspectRatio`` (see ``aspectRatio``); the
/// pixel resolution is the model's, or ``ImageResolution`` when set. See
/// spec §6.1.
public enum ImageSize: String, Sendable, CaseIterable, Codable {
    /// 1:1 aspect ratio (default).
    case square
    /// Vertical aspect ratio (e.g. 9:16).
    case portrait
    /// Horizontal aspect ratio (e.g. 16:9).
    case landscape
}
