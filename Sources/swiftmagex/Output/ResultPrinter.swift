import Foundation
import SwiftMageXKit

/// Renders command results to stdout / stderr.
///
/// Two output modes per spec §12: human-readable plain text (default) and
/// a single JSON object under `--json`. Stub until milestones 2, 3, 5 wire
/// the real result payloads through.
struct ResultPrinter {
    /// Whether to emit JSON to stdout instead of plain text.
    let json: Bool
    /// Whether to emit diagnostic messages to stderr.
    let verbose: Bool

    /// Creates a printer.
    init(json: Bool, verbose: Bool) {
        self.json = json
        self.verbose = verbose
    }

    /// Print a successful result describing the absolute paths produced.
    ///
    /// - Parameters:
    ///   - outputs: Absolute file URLs produced by the command.
    ///   - provider: Identifier of the provider that produced the result, if any.
    ///   - model: Model identifier used, if any.
    func printSuccess(outputs: [URL], provider: String?, model: String?) {
        // TODO(milestone 6): structured JSON encoder with the schema from spec §12.
        _ = outputs
        _ = provider
        _ = model
        _ = json
    }

    /// Print an error in the appropriate output mode.
    func printError(_ error: SwiftMageXError) {
        // TODO(milestone 6): JSON / text error envelope per spec §12.
        _ = error
    }

    /// Print a diagnostic line to stderr if `--verbose` is on.
    func diagnostic(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }
}
