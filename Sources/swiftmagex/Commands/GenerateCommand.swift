import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex generate <prompt> [options]` — image generation via Gemini.
///
/// Per spec §6.1. Argument surface is final; `run()` is a stub until milestone 5.
struct GenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate an image from a text prompt."
    )

    @Argument(help: "Text prompt describing the image to generate.")
    var prompt: String

    @Option(name: [.customShort("o"), .long], help: "Destination file or directory. Defaults to the current directory.")
    var output: String = "./"

    @Option(
        name: [.customShort("s"), .long],
        help: ArgumentHelp("Aspect ratio of the generated image.", valueName: "square|portrait|landscape")
    )
    var size: ImageSize = .square

    @Option(name: [.customShort("n"), .long], help: "Number of variants to generate (1–4).")
    var count: Int = 1

    @Option(name: .long, help: "Seed for reproducibility. Support is provider-dependent.")
    var seed: UInt64?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Image model identifier. Built-in: \(ModelCatalog.all.map(\.id).joined(separator: ", ")). Unknown IDs route by `imagen-`/`gemini-` prefix.",
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
    }

    func run() async throws {
        let printer = ResultPrinter(json: globals.json, verbose: globals.verbose)
        let request = GenerationRequest(
            prompt: prompt,
            size: size,
            count: count,
            seed: seed,
            model: model
        )
        let outputTarget = output.isEmpty ? nil : output

        let cache = CacheOption.makeCache(from: globals.cacheDir)

        do {
            let written = try await SwiftMageXOrchestrator.generate(
                request: request,
                output: outputTarget,
                cache: cache
            )
            for image in written where image.wasCached {
                printer.diagnostic("cache hit: \(image.path.path)")
            }
            let outputs = CacheOption.makeOutputs(from: written, cacheConfigured: cache != nil)
            printer.printSuccess(
                command: "generate",
                outputs: outputs,
                provider: ModelCatalog.family(for: model).rawValue,
                model: model
            )
        } catch let error as SwiftMageXError {
            printer.printError(error, command: "generate")
            throw ExitCode(error.exitCode)
        }
    }
}

extension ImageSize: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    public static var allValueStrings: [String] { Self.allCases.map(\.rawValue) }
}
