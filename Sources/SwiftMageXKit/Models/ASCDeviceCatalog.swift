import Foundation

/// One App Store Connect iPhone screenshot slot.
///
/// Dimensions are stored in portrait; ``dimensions(for:)`` swaps them for
/// landscape. App Store Connect rejects uploads that don't match a supported
/// slot pixel-for-pixel, so these values are exact.
public struct ASCDeviceSize: Sendable, Equatable {
    /// Stable identifier used on the command line, e.g. `iphone-6.9`.
    public let id: String
    /// Human-readable label, e.g. `iPhone 6.9"`.
    public let label: String
    /// Portrait width in pixels.
    public let width: Int
    /// Portrait height in pixels.
    public let height: Int

    public init(id: String, label: String, width: Int, height: Int) {
        self.id = id
        self.label = label
        self.width = width
        self.height = height
    }

    /// The pixel dimensions for `orientation` — portrait as stored, or swapped
    /// for landscape.
    public func dimensions(for orientation: Orientation) -> (width: Int, height: Int) {
        switch orientation {
        case .portrait: return (width, height)
        case .landscape: return (height, width)
        }
    }
}

/// Registry of the App Store Connect iPhone screenshot slots the CLI surfaces.
///
/// These are the three classic ASC iPhone upload sizes (Apple's screenshot
/// specifications). When no device is requested, only the 6.9" size is produced
/// because App Store Connect auto-scales the remaining device classes from it.
/// Newer-hardware variants (1320×2868, 1284×2778) can be added here without
/// touching anything else.
public enum ASCDeviceCatalog {
    /// Produced by default when the caller names no device.
    public static let defaultDeviceIDs = ["iphone-6.9"]

    /// All built-in iPhone screenshot slots, portrait.
    public static let all: [ASCDeviceSize] = [
        .init(id: "iphone-6.9", label: "iPhone 6.9\"", width: 1290, height: 2796),
        .init(id: "iphone-6.5", label: "iPhone 6.5\"", width: 1242, height: 2688),
        .init(id: "iphone-5.5", label: "iPhone 5.5\"", width: 1242, height: 2208),
    ]

    /// Returns the slot for an exact `id` match, or `nil` if unknown.
    public static func size(for id: String) -> ASCDeviceSize? {
        all.first { $0.id == id }
    }

    /// Resolves a list of device ids to their slots.
    ///
    /// The literal `all` expands to every catalogued slot (deduplicated, in
    /// catalog order). An empty list resolves to the default. An unknown id
    /// throws ``SwiftMageXError/invalidInput(_:)`` so the frontends report it
    /// with exit code 2.
    public static func sizes(for ids: [String]) throws -> [ASCDeviceSize] {
        let requested = ids.isEmpty ? defaultDeviceIDs : ids
        if requested.contains("all") {
            return all
        }
        var seen = Set<String>()
        var resolved: [ASCDeviceSize] = []
        for id in requested where seen.insert(id).inserted {
            guard let size = size(for: id) else {
                let known = all.map(\.id).joined(separator: ", ")
                throw SwiftMageXError.invalidInput(
                    "unknown device '\(id)' (known: \(known), or 'all')"
                )
            }
            resolved.append(size)
        }
        return resolved
    }
}
