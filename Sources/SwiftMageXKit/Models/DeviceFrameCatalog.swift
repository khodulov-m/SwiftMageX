import Foundation

/// One bundled device bezel — a PNG with a transparent screen cutout, shipped
/// inside `SwiftMageXKit` via `Bundle.module`.
///
/// Decoupled from ``ASCDeviceSize`` on purpose: a device id may have zero, one,
/// or many bundled frames (e.g. colour variants). Each entry just *points* at
/// an ASC slot via ``deviceID`` so the orchestrator can auto-pick one when the
/// user passes `--device <id>` without `--frame`.
public struct DeviceFrame: Sendable, Equatable {
    /// Stable identifier used on the command line, e.g.
    /// `iphone-6.5-pommeplate-spacegray`.
    public let id: String
    /// The ``ASCDeviceSize/id`` this frame is meant for.
    public let deviceID: String
    /// Human-readable label including provenance.
    public let label: String
    /// Bundle resource basename (without extension) inside `Bundle.module`.
    public let resource: String
    /// File extension of the resource (typically `png`).
    public let resourceExtension: String
    /// Optional explicit screen cutout. `nil` means the orchestrator falls back
    /// to alpha auto-detection (slower but resilient to manifest drift).
    public let screenRect: DeviceFrameSpec.ScreenRect?
    /// Whether this is the default frame for its `deviceID` when multiple
    /// frames share the same device.
    public let isDefault: Bool
    /// Upstream source URL for attribution.
    public let source: String?
    /// SPDX-style licence identifier of the source, e.g. `CC0-1.0`.
    public let license: String?

    /// Resolves the on-disk URL of the bezel inside the kit's resource bundle.
    public func url() throws -> URL {
        try resolveURL(in: .module)
    }

    /// Bundle-injectable variant for tests.
    func resolveURL(in bundle: Bundle) throws -> URL {
        guard let url = bundle.url(
            forResource: resource,
            withExtension: resourceExtension,
            subdirectory: DeviceFrameCatalog.resourceSubdirectory
        ) else {
            throw SwiftMageXError.io(
                "bundled device frame '\(id)' is missing from the resource bundle"
            )
        }
        return url
    }
}

/// Registry of device bezels bundled with the kit. Loaded once from
/// `Resources/Frames/frames.json` at first access.
///
/// Adding a new frame is a JSON + PNG drop, no code change — the manifest is
/// the single source of truth.
public enum DeviceFrameCatalog {
    /// Every bundled frame, in manifest order. Cached after the first call.
    public static var all: [DeviceFrame] { cached.frames }

    /// Lookup by frame id; returns `nil` for unknown ids.
    public static func frame(id: String) -> DeviceFrame? {
        cached.byID[id]
    }

    /// The default bundled frame for an ASC device id, or `nil` when no frame
    /// has been bundled for that device yet.
    ///
    /// Prefers the entry with `default: true`; falls back to the first match in
    /// manifest order.
    public static func defaultFrame(for deviceID: String) -> DeviceFrame? {
        let matches = cached.frames.filter { $0.deviceID == deviceID }
        return matches.first(where: \.isDefault) ?? matches.first
    }

    /// Manifest schema version the loader supports.
    public static let supportedSchemaVersion = 1

    /// The kit's own `Bundle.module`, exposed so tests can drive the loader
    /// against the production resource bundle (test targets have their own
    /// `.module` that does not see the kit's resources).
    static var resourceBundle: Bundle { .module }

    /// Subdirectory inside `Bundle.module` where every bundled frame asset
    /// (plus the manifest) lives. SwiftPM preserves the directory structure
    /// declared by `.copy("Resources/Frames")`, so `url(forResource:…)` must
    /// be told to look here rather than the bundle root.
    static let resourceSubdirectory = "Frames"

    // MARK: - Loading

    private struct Cache: Sendable {
        let frames: [DeviceFrame]
        let byID: [String: DeviceFrame]
    }

    private static let cached: Cache = loadOrCrash()

    private static func loadOrCrash() -> Cache {
        do {
            let frames = try load(bundle: .module)
            var byID: [String: DeviceFrame] = [:]
            byID.reserveCapacity(frames.count)
            for frame in frames {
                if byID[frame.id] != nil {
                    fatalError("DeviceFrameCatalog: duplicate frame id '\(frame.id)' in frames.json")
                }
                byID[frame.id] = frame
            }
            return Cache(frames: frames, byID: byID)
        } catch {
            fatalError("DeviceFrameCatalog: failed to load frames.json — \(error)")
        }
    }

    /// Reads and decodes `frames.json` from `bundle`. Exposed for tests so they
    /// can verify the manifest without relying on the cached singleton.
    static func load(bundle: Bundle) throws -> [DeviceFrame] {
        guard let url = bundle.url(
            forResource: "frames",
            withExtension: "json",
            subdirectory: resourceSubdirectory
        ) else {
            throw SwiftMageXError.io("frames.json is missing from the kit's resource bundle")
        }
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw SwiftMageXError.io(
                "frames.json schema version \(manifest.schemaVersion) is not supported (expected \(supportedSchemaVersion))"
            )
        }
        return manifest.frames.map(\.asDeviceFrame)
    }

    // MARK: - Manifest decoding

    private struct Manifest: Decodable {
        let schemaVersion: Int
        let frames: [Entry]
    }

    private struct Entry: Decodable {
        let id: String
        let deviceID: String
        let label: String
        let resource: String
        let `extension`: String
        let screenRect: ScreenRectEntry?
        let `default`: Bool?
        let source: String?
        let license: String?

        var asDeviceFrame: DeviceFrame {
            DeviceFrame(
                id: id,
                deviceID: deviceID,
                label: label,
                resource: resource,
                resourceExtension: `extension`,
                screenRect: screenRect.map {
                    DeviceFrameSpec.ScreenRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
                },
                isDefault: `default` ?? false,
                source: source,
                license: license
            )
        }
    }

    private struct ScreenRectEntry: Decodable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }
}
