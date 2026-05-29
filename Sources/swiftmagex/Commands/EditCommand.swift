import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex edit <input> <prompt> [options]` — image-to-image / inpainting
/// via Gemini's `:generateContent` endpoint. The source image (and optional
/// mask) are sent as inline parts alongside the text prompt.
struct EditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit an image with a Gemini model (image-to-image / inpainting)."
    )

    @Argument(help: "Source image file to edit (PNG or JPEG).")
    var input: String

    @Argument(help: "Text prompt describing the edit.")
    var prompt: String

    @Option(
        name: .long,
        help: "Optional grayscale/binary mask (PNG or JPEG). White marks the region to edit."
    )
    var mask: String?

    @Option(name: [.customShort("o"), .long], help: "Destination file or directory. Defaults to the current directory.")
    var output: String = "./"

    @Option(name: [.customShort("n"), .long], help: "Number of variants to generate (1–4).")
    var count: Int = 1

    @Option(name: .long, help: "Seed for reproducibility. Support is provider-dependent.")
    var seed: UInt64?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Image model identifier. Edit requires a Gemini model (Imagen does not accept inline image inputs).",
            valueName: "model"
        )
    )
    var model: String = ModelCatalog.defaultModelID

    @OptionGroup var globals: GlobalOptions

    func validate() throws {
        guard (1...4).contains(count) else {
            throw ValidationError("--count must be between 1 and 4 (got \(count)).")
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("Prompt must not be empty.")
        }
        guard ModelCatalog.family(for: model) == .gemini else {
            throw ValidationError(
                "--model must be a Gemini model for edit (got \(model))."
            )
        }
    }

    func run() async throws {
        let printer = ResultPrinter(json: globals.json, verbose: globals.verbose)
        let request = GenerationRequest(
            prompt: prompt,
            size: .square,
            count: count,
            seed: seed,
            model: model
        )
        let outputTarget = output.isEmpty ? nil : output

        do {
            let written = try await SwiftMageXOrchestrator.edit(
                input: input,
                mask: mask,
                request: request,
                output: outputTarget
            )
            let outputs = written.map { image in
                JSONResultEnvelope.Output(
                    path: image.path.path,
                    format: image.format,
                    width: image.width,
                    height: image.height
                )
            }
            printer.printSuccess(
                command: "edit",
                outputs: outputs,
                provider: ModelCatalog.family(for: model).rawValue,
                model: model
            )
        } catch let error as SwiftMageXError {
            printer.printError(error, command: "edit")
            throw ExitCode(error.exitCode)
        }
    }
}
