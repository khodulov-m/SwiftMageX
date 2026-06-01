import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex edit <input> <prompt> [options]` — image-to-image / multi-image
/// / inpainting via Gemini's `:generateContent` endpoint. The primary input,
/// any `--reference` images, and an optional mask are sent as inline parts
/// alongside the text prompt.
struct EditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit an image with a Gemini model (image-to-image / multi-image / inpainting)."
    )

    @Argument(help: "Primary source image to edit (PNG or JPEG).")
    var input: String

    @Argument(help: "Text prompt describing the edit.")
    var prompt: String

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Additional reference image (PNG or JPEG). Repeatable — every `--reference` adds another inline image part the prompt can compose against."
    )
    var reference: [String] = []

    @Option(
        name: .long,
        help: "Optional grayscale/binary mask (PNG or JPEG). White marks the region to edit on the primary input."
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

        let cache = CacheOption.makeCache(from: globals.cacheDir)

        do {
            let written = try await SwiftMageXOrchestrator.edit(
                input: input,
                references: reference,
                mask: mask,
                request: request,
                output: outputTarget,
                cache: cache
            )
            for image in written where image.wasCached {
                printer.diagnostic("cache hit: \(image.path.path)")
            }
            let outputs = CacheOption.makeOutputs(from: written, cacheConfigured: cache != nil)
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
