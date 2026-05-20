import Foundation
import SwiftMageXKit

/// Renders command results to stdout / stderr per spec §12.
///
/// Stream routing is fixed by the spec:
///   - JSON mode: result envelope → stdout, whether success or error, so the
///     calling agent can read everything from a single stream.
///   - Plain mode: success → stdout (one path per line), errors → stderr.
///   - Diagnostics under `--verbose` always go to stderr regardless of mode.
struct ResultPrinter {
    /// Whether to emit JSON to stdout instead of plain text.
    let json: Bool
    /// Whether to emit diagnostic messages to stderr.
    let verbose: Bool

    init(json: Bool, verbose: Bool) {
        self.json = json
        self.verbose = verbose
    }

    /// Print a successful result describing the absolute paths produced.
    func printSuccess(
        command: String,
        outputs: [JSONResultEnvelope.Output],
        provider: String? = nil,
        model: String? = nil
    ) {
        if json {
            let envelope = JSONResultEnvelope.success(
                command: command,
                outputs: outputs,
                provider: provider,
                model: model
            )
            write(envelope: envelope, to: .stdout)
        } else {
            for output in outputs {
                writeLine(output.path, to: .stdout)
            }
        }
    }

    /// Print an error in the appropriate output mode.
    func printError(_ error: SwiftMageXError, command: String) {
        if json {
            let envelope = JSONResultEnvelope.failure(command: command, error: error)
            write(envelope: envelope, to: .stdout)
        } else {
            writeLine(error.description, to: .stderr)
        }
    }

    /// Print a diagnostic line to stderr if `--verbose` is on.
    func diagnostic(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        writeLine(message(), to: .stderr)
    }

    // MARK: - Helpers

    private enum Stream {
        case stdout
        case stderr

        var handle: FileHandle {
            switch self {
            case .stdout: return .standardOutput
            case .stderr: return .standardError
            }
        }
    }

    private func write(envelope: JSONResultEnvelope, to stream: Stream) {
        do {
            let data = try envelope.jsonData()
            stream.handle.write(data)
            stream.handle.write(Data("\n".utf8))
        } catch {
            // Encoding the envelope should be infallible for the inputs we
            // construct; if it ever isn't, fall back to a single text line so
            // the program stays useful rather than silently dropping output.
            writeLine("error encoding JSON envelope: \(error.localizedDescription)", to: .stderr)
        }
    }

    private func writeLine(_ message: String, to stream: Stream) {
        stream.handle.write(Data((message + "\n").utf8))
    }
}
