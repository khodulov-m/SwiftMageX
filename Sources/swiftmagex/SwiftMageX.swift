import ArgumentParser
import Foundation

/// The `swiftmagex` CLI command tree.
///
/// Routes into one of the subcommands per spec §6 (`edit`, `composite`,
/// `appstore`, `remove-bg`, and `crop` are post-0.1 local additions; `edit`
/// shares Gemini's `:generateContent` shape with `generate`). All actual work
/// lives in `SwiftMageXKit`; this target is a thin frontend that parses
/// arguments and prints results.
struct SwiftMageX: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftmagex",
        abstract: "Generate and process images from the terminal.",
        version: "0.2.0",
        subcommands: [
            GenerateCommand.self,
            EditCommand.self,
            ResizeCommand.self,
            TextCommand.self,
            CompositeCommand.self,
            AppStoreCommand.self,
            RemoveBackgroundCommand.self,
            CropCommand.self,
            IconCommand.self,
        ]
    )
}

/// Process entry point.
///
/// We deliberately don't put `@main` on ``SwiftMageX`` and lean on
/// ArgumentParser's default runner, because that runner exits with
/// `EX_USAGE` (64) on *any* parse or `validate()` failure. Spec §13 mandates
/// exit code **2** for invalid arguments/input, and kit-level
/// ``SwiftMageXError/invalidInput(_:)`` already maps to 2 — so the default
/// runner would make the same class of error report two different codes
/// (64 from `validate()`, 2 from the kit). This wrapper drives the identical
/// parse → run flow and remaps only that one code so the contract is uniform.
@main
struct SwiftMageXEntry {
    static func main() async {
        do {
            var command = try SwiftMageX.parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(remapping: error)
        }
    }

    /// Terminates the process, mapping ArgumentParser's usage/validation
    /// failures (default `EX_USAGE` = 64) onto the spec §13 invalid-input
    /// code (2). An ``ExitCode`` thrown by a subcommand's `run()` already
    /// carries the right code — and the command already printed its message
    /// via `ResultPrinter` — so it passes through untouched. `--help` /
    /// `--version` keep their stdout + exit-0 behaviour.
    private static func exit(remapping error: Error) -> Never {
        // A subcommand's run() throws ExitCode with the spec code already set,
        // having printed its own diagnostics — don't reprint or remap.
        if let exitCode = error as? ExitCode {
            Foundation.exit(exitCode.rawValue)
        }

        // Otherwise this is ArgumentParser's own flow: a parse error, a
        // validation error, or a clean `--help` / `--version` exit.
        let code = SwiftMageX.exitCode(for: error)
        if code == .success {
            // Help / version text belongs on stdout.
            print(SwiftMageX.fullMessage(for: error))
            Foundation.exit(0)
        }
        FileHandle.standardError.write(
            Data((SwiftMageX.fullMessage(for: error) + "\n").utf8)
        )
        // EX_USAGE (64) → 2 per spec §13; any other failure keeps its code.
        Foundation.exit(code == .validationFailure ? 2 : code.rawValue)
    }
}
