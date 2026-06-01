import Foundation
import SwiftMageXKit

/// Shared helpers for the `--cache-dir` global flag. Used by `generate` and
/// `edit` to resolve the directory (with `~` expansion against
/// `currentDirectoryPath` when relative) and to project a per-image
/// `wasCached` flag into the JSON output envelope.
enum CacheOption {
    /// Build a ``ResponseCache`` from the resolved global flag, or return
    /// `nil` when the user didn't pass `--cache-dir`. No I/O happens here —
    /// the cache itself lazily creates the directory on first write.
    static func makeCache(from path: String?) -> (any ResponseCache)? {
        guard let raw = path, !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let url = URL(fileURLWithPath: expanded, relativeTo: cwd).standardizedFileURL
        return FileSystemResponseCache(directory: url)
    }

    /// Maps a list of ``WrittenImage`` to the JSON-output `Output` shape,
    /// surfacing `cached` only when a cache was configured for the call.
    /// Omitting the field when the user didn't opt in keeps the JSON shape
    /// stable for everyone else.
    static func makeOutputs(
        from written: [WrittenImage],
        cacheConfigured: Bool
    ) -> [JSONResultEnvelope.Output] {
        written.map { image in
            JSONResultEnvelope.Output(
                path: image.path.path,
                format: image.format,
                width: image.width,
                height: image.height,
                cached: cacheConfigured ? image.wasCached : nil
            )
        }
    }
}
