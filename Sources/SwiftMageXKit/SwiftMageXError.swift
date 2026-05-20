import Foundation

/// The unified error type thrown by every layer of SwiftMageX.
///
/// Each case corresponds to a semantic category of failure that the frontends
/// (CLI and MCP server) map to a specific exit code or MCP tool error per the
/// project specification §13.
public enum SwiftMageXError: Error, Sendable, Equatable {
    /// Invalid user input — for example, a malformed flag or an out-of-range value.
    /// Maps to CLI exit code `2`.
    case invalidInput(String)

    /// Configuration error such as a missing API key or unreadable file path.
    /// Maps to CLI exit code `4`.
    case configuration(String)

    /// Failure from the upstream image-generation provider (HTTP error,
    /// quota exhaustion after retries, content moderation, etc.).
    /// Maps to CLI exit code `3`.
    case provider(String)

    /// Failure during a local raster operation (decode, resize, text overlay).
    /// Maps to CLI exit code `1`.
    case raster(String)

    /// File I/O failure (read, write, permission). Maps to CLI exit code `1`.
    case io(String)
}

extension SwiftMageXError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidInput(let message): return "Invalid input: \(message)"
        case .configuration(let message): return "Configuration error: \(message)"
        case .provider(let message): return "Provider error: \(message)"
        case .raster(let message): return "Raster error: \(message)"
        case .io(let message): return "I/O error: \(message)"
        }
    }
}

extension SwiftMageXError {
    /// The process exit code that corresponds to this error category.
    ///
    /// Frontends use this to terminate with a predictable status; see spec §13.
    public var exitCode: Int32 {
        switch self {
        case .invalidInput: return 2
        case .provider: return 3
        case .configuration: return 4
        case .raster, .io: return 1
        }
    }

    /// A stable identifier used in the JSON error envelope (spec §12) and in
    /// MCP tool errors (spec §7). Keep these strings frozen — agents key off
    /// them when deciding how to react.
    public var category: String {
        switch self {
        case .invalidInput: return "invalid_input"
        case .provider: return "provider"
        case .configuration: return "configuration"
        case .raster: return "raster"
        case .io: return "io"
        }
    }

    /// The human-readable detail attached to this error case. Distinct from
    /// `description`, which is prefixed with the category for plain-text use.
    public var message: String {
        switch self {
        case .invalidInput(let m),
             .configuration(let m),
             .provider(let m),
             .raster(let m),
             .io(let m):
            return m
        }
    }
}
