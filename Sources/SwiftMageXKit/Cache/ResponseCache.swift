import Foundation

/// One image stored in (or retrieved from) the cache. Raw provider bytes
/// plus the container format — enough for the orchestrator to reconstruct
/// a ``GeneratedImage`` on a hit and pump it through the same writer path
/// that fresh provider responses use.
public struct CachedImage: Sendable, Equatable {
    public var data: Data
    public var format: ImageFormat

    public init(data: Data, format: ImageFormat) {
        self.data = data
        self.format = format
    }
}

/// A cache entry: the ordered list of images that a prior call to the same
/// key returned.
public struct CachedResponse: Sendable, Equatable {
    public var images: [CachedImage]

    public init(images: [CachedImage]) {
        self.images = images
    }
}

/// Read/write interface for a content-addressed response cache. The
/// orchestrator calls ``lookup(_:)`` before invoking the provider and
/// ``store(_:_:)`` after a fresh response; both operations are best-effort
/// and any thrown error is treated as a cache miss / silent skip by the
/// orchestrator (so a broken cache never poisons a real generation).
public protocol ResponseCache: Sendable {
    func lookup(_ key: String) throws -> CachedResponse?
    func store(_ key: String, response: CachedResponse) throws
}

/// Filesystem-backed ``ResponseCache``.
///
/// Layout per entry — the cache directory holds one subdirectory per key:
///
/// ```
/// <directory>/<key>/
///   meta.json    { count, createdAt, toolVersion, images: [{format, file}] }
///   0.png        // raw provider bytes for image 0
///   1.png        // ... and so on for `count > 1`
/// ```
///
/// Writes are staged into a sibling `<key>.tmp.<uuid>` directory and renamed
/// into place so a partially-written entry is never visible to a concurrent
/// reader. If a final directory already exists at `<key>`, the existing
/// entry is left alone — content addressing guarantees its bytes satisfy
/// the same key, and the cache's purpose is "any valid hit," not "freshest."
public struct FileSystemResponseCache: ResponseCache {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func lookup(_ key: String) throws -> CachedResponse? {
        let fm = FileManager.default
        let entry = directory.appendingPathComponent(key, isDirectory: true)
        let meta = entry.appendingPathComponent("meta.json")
        guard fm.fileExists(atPath: meta.path) else { return nil }

        let metaData = try Data(contentsOf: meta)
        let payload = try JSONDecoder().decode(MetaPayload.self, from: metaData)

        var images: [CachedImage] = []
        images.reserveCapacity(payload.images.count)
        for descriptor in payload.images {
            let imageURL = entry.appendingPathComponent(descriptor.file)
            let bytes = try Data(contentsOf: imageURL)
            images.append(CachedImage(data: bytes, format: descriptor.format))
        }
        return CachedResponse(images: images)
    }

    public func store(_ key: String, response: CachedResponse) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let entry = directory.appendingPathComponent(key, isDirectory: true)
        // Content addressing means an existing entry is by definition valid
        // for this key — avoid the rename race entirely by skipping.
        if fm.fileExists(atPath: entry.path) { return }

        let tmp = directory.appendingPathComponent(
            "\(key).tmp.\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        // If the move below succeeds, `tmp` no longer exists and the cleanup
        // is a no-op; if anything else throws partway through, we drop the
        // half-written staging dir so the next call starts clean.
        var moved = false
        defer {
            if !moved {
                try? fm.removeItem(at: tmp)
            }
        }

        var descriptors: [MetaPayload.ImageDescriptor] = []
        descriptors.reserveCapacity(response.images.count)
        for (index, image) in response.images.enumerated() {
            let file = "\(index).\(image.format.fileExtension)"
            try image.data.write(to: tmp.appendingPathComponent(file))
            descriptors.append(.init(format: image.format, file: file))
        }

        let payload = MetaPayload(
            count: response.images.count,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            toolVersion: Configuration.toolVersion,
            images: descriptors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let metaData = try encoder.encode(payload)
        try metaData.write(to: tmp.appendingPathComponent("meta.json"))

        do {
            try fm.moveItem(at: tmp, to: entry)
            moved = true
        } catch {
            // Another writer beat us to the rename — their entry is equally
            // valid for this key, so swallow the error.
            if fm.fileExists(atPath: entry.path) {
                moved = false  // let `defer` clean tmp up
                return
            }
            throw error
        }
    }

    // MARK: - On-disk schema

    private struct MetaPayload: Codable {
        let count: Int
        let createdAt: String
        let toolVersion: String
        let images: [ImageDescriptor]

        struct ImageDescriptor: Codable {
            let format: ImageFormat
            let file: String
        }
    }
}
