import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex remove-bg <input> [options]` — local background removal.
///
/// Uses Vision's on-device foreground segmentation. No AI provider, no API key,
/// zero quota. The cutout carries alpha, so output is always written as PNG.
struct RemoveBackgroundCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove-bg",
        abstract: "Remove an image background locally with Vision — no AI, no key."
    )

    @Argument(help: "Source image file.")
    var input: String

    @Option(name: [.customShort("o"), .long], help: "Destination PNG file. Defaults to a sibling of the source.")
    var output: String?

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let printer = ResultPrinter(json: globals.json, verbose: globals.verbose)

        // The output is always PNG (alpha); warn if the user named a different
        // extension so the coerced filename isn't a surprise.
        if let output = output,
           !output.lowercased().hasSuffix(".\(ImageFormat.png.fileExtension)") {
            printer.diagnostic("background removal requires alpha; output will be written as PNG")
        }

        do {
            let written = try SwiftMageXOrchestrator.removeBackground(
                input: input,
                output: output
            )
            printer.printSuccess(
                command: "remove-bg",
                outputs: [JSONResultEnvelope.Output(
                    path: written.path.path,
                    format: written.format,
                    width: written.width,
                    height: written.height
                )]
            )
        } catch let error as SwiftMageXError {
            printer.printError(error, command: "remove-bg")
            throw ExitCode(error.exitCode)
        }
    }
}
