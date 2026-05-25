import Foundation

/// Orientation of an App Store screenshot canvas.
///
/// ASC device sizes are catalogued in portrait (see ``ASCDeviceCatalog``);
/// `landscape` swaps width and height for landscape uploads.
public enum Orientation: String, Sendable, CaseIterable, Codable {
    /// Taller than wide — the default for iPhone screenshots.
    case portrait
    /// Wider than tall — width and height swapped from the catalogued size.
    case landscape
}
