import Foundation
import SwiftMageXKit

/// Renders command results to stdout / stderr.
///
/// Two output modes per spec §12: human-readable plain text (default) and
/// a single JSON object under `--json`. Milestone 6 lands the full JSON
/// schema; today the minimal surface (status + outputs) is in place so the
/// `--json` flag is not a lie.
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
    ///   - command: The command name ("generate", "resize", "text").
    ///   - outputs: Absolute file URLs produced by the command.
    ///   - provider: Identifier of the provider that produced the result, if any.
    ///   - model: Model identifier used, if any.
    func printSuccess(
        command: String,
        outputs: [SuccessOutput],
        provider: String? = nil,
        model: String? = nil
    ) {
        if json {
            writeJSON(command: command, outputs: outputs, provider: provider, model: model)
        } else {
            for o in outputs {
                print(o.path.path)
            }
        }
    }

    /// Print an error in the appropriate output mode.
    func printError(_ error: SwiftMageXError) {
        // TODO(milestone 6): JSON / text error envelope per spec §12.
        FileHandle.standardError.write(Data((error.description + "\n").utf8))
    }

    /// Print a diagnostic line to stderr if `--verbose` is on.
    func diagnostic(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }

    // MARK: - JSON encoding

    private func writeJSON(
        command: String,
        outputs: [SuccessOutput],
        provider: String?,
        model: String?
    ) {
        var root: [String: Any] = [
            "status": "ok",
            "command": command,
            "outputs": outputs.map { output -> [String: Any] in
                var entry: [String: Any] = [
                    "path": output.path.path,
                    "format": output.format.rawValue,
                ]
                if let width = output.width { entry["width"] = width }
                if let height = output.height { entry["height"] = height }
                return entry
            },
        ]
        if let provider { root["provider"] = provider }
        if let model { root["model"] = model }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            // Falling back to text keeps the program useful when JSON encoding
            // somehow fails — should be unreachable with this input shape.
            for o in outputs { print(o.path.path) }
        }
    }
}

/// A single output produced by a command, for use in `printSuccess`.
struct SuccessOutput {
    let path: URL
    let format: ImageFormat
    let width: Int?
    let height: Int?

    init(path: URL, format: ImageFormat, width: Int? = nil, height: Int? = nil) {
        self.path = path
        self.format = format
        self.width = width
        self.height = height
    }
}
