import Foundation

/// Resolves a user-supplied output target to an absolute file URL (spec §12).
///
/// Both the CLI and the MCP server depend on absolute output paths, so the
/// resolution logic lives in the kit. When `target` names a directory (or is
/// `nil`), files are named with the pattern
/// `swiftmagex_{timestamp}_{index}.{ext}`. When `target` names a specific
/// file, that name is used, with an index suffix inserted before the
/// extension when `count > 1`.
public enum OutputPath {
    /// Resolves an array of absolute file URLs.
    ///
    /// - Parameters:
    ///   - target: The user-supplied `--output` value (a directory, a file, or `nil`).
    ///   - count: Number of files to be produced (1 or more).
    ///   - format: Output format — used both to choose an extension when a
    ///     directory target is given, and to override an inconsistent
    ///     user-supplied extension when one is.
    ///   - timestamp: Used in directory-target filenames. Defaults to "now".
    ///   - currentDirectoryPath: Resolves relative `target` values. Defaults
    ///     to the process cwd; injectable for tests.
    public static func resolve(
        target: String?,
        count: Int,
        format: ImageFormat,
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> [URL] {
        precondition(count >= 1, "count must be >= 1")
        let cwd = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)

        let isDirectoryTarget: Bool
        let baseURL: URL
        if let raw = target?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let resolved = URL(fileURLWithPath: raw, relativeTo: cwd).standardizedFileURL
            // Treat the target as a directory when:
            //   - it exists and is a directory, or
            //   - the user wrote a trailing slash.
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir)
            if exists {
                isDirectoryTarget = isDir.boolValue
            } else {
                isDirectoryTarget = raw.hasSuffix("/")
            }
            baseURL = resolved
        } else {
            isDirectoryTarget = true
            baseURL = cwd.standardizedFileURL
        }

        if isDirectoryTarget {
            let stamp = compactTimestamp(timestamp)
            return (1...count).map { idx in
                baseURL
                    .appendingPathComponent("swiftmagex_\(stamp)_\(idx).\(format.fileExtension)")
                    .standardizedFileURL
            }
        }

        // Specific filename target.
        let parent = baseURL.deletingLastPathComponent()
        let stem = baseURL.deletingPathExtension().lastPathComponent
        let userExt = baseURL.pathExtension
        let ext = userExt.isEmpty ? format.fileExtension : userExt

        if count == 1 {
            return [parent.appendingPathComponent("\(stem).\(ext)").standardizedFileURL]
        }
        return (1...count).map { idx in
            parent.appendingPathComponent("\(stem)_\(idx).\(ext)").standardizedFileURL
        }
    }

    /// Resolves a single absolute file URL — convenience for commands that
    /// only ever produce one file (`resize`, `text`).
    public static func resolveSingle(
        target: String?,
        sourceURL: URL,
        format: ImageFormat,
        timestamp: Date = Date(),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> URL {
        // If no explicit target, name the output next to the source per spec §6.2.
        if (target?.trimmingCharacters(in: .whitespacesAndNewlines)).map({ $0.isEmpty }) ?? true {
            let parent = sourceURL.deletingLastPathComponent()
            let stamp = compactTimestamp(timestamp)
            return parent
                .appendingPathComponent("swiftmagex_\(stamp)_1.\(format.fileExtension)")
                .standardizedFileURL
        }
        let urls = try resolve(
            target: target,
            count: 1,
            format: format,
            timestamp: timestamp,
            currentDirectoryPath: currentDirectoryPath
        )
        return urls[0]
    }

    /// ISO-8601 compact form used in default filenames, e.g. `20260519T103045Z`.
    static func compactTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let iso = formatter.string(from: date)
        // 2026-05-19T10:30:45Z → 20260519T103045Z
        return iso.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
    }
}
