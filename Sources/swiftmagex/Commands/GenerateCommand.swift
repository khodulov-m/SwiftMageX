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

    @Option(name: [.customShort("o"), .long], help: "Destination file or directory. Defaults to $SWIFTMAGEX_OUTPUT_DIR or the current directory.")
    var output: String?

    @Option(
        name: [.customShort("s"), .long],
        help: ArgumentHelp(
            "Aspect-ratio preset: square (1:1), portrait (9:16), landscape (16:9). Without it (or --aspect-ratio) Gemini picks its own framing.",
            valueName: "square|portrait|landscape"
        )
    )
    var size: ImageSize?

    @Option(
        name: [.customShort("a"), .long],
        help: ArgumentHelp(
            "Exact aspect ratio: \(AspectRatio.allCases.map(\.rawValue).joined(separator: ", ")). Mutually exclusive with --size.",
            valueName: "W:H"
        )
    )
    var aspectRatio: AspectRatio?

    @Option(
        name: [.customShort("r"), .long],
        help: ArgumentHelp(
            "Output resolution tier: \(ImageResolution.allCases.map(\.rawValue).joined(separator: ", ")). Defaults to the model's own (1K). Gemini only.",
            valueName: "tier"
        )
    )
    var resolution: ImageResolution?

    @Option(name: [.customShort("n"), .long], help: "Number of variants to generate (1–4).")
    var count: Int = 1

    @Option(name: .long, help: "Seed for reproducibility. Support is provider-dependent.")
    var seed: UInt64?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Image model identifier. Built-in: \(ModelCatalog.all.map(\.id).joined(separator: ", ")). Other IDs are passed to Gemini as-is.",
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
        guard size == nil || aspectRatio == nil else {
            throw ValidationError("--size and --aspect-ratio are mutually exclusive; pass one.")
        }
    }

    /// The exact ratio to send: `--aspect-ratio`, else the `--size` preset's,
    /// else `nil` so the model picks its own framing.
    var requestedAspectRatio: AspectRatio? { aspectRatio ?? size?.aspectRatio }

    func run() async throws {
        let printer = ResultPrinter(json: globals.json, verbose: globals.verbose)
        let request = GenerationRequest(
            prompt: prompt,
            count: count,
            seed: seed,
            model: model,
            aspectRatio: requestedAspectRatio,
            resolution: resolution
        )
        let outputTarget = Configuration.resolvedOutputTarget(explicit: output)

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
                provider: "gemini",
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

extension AspectRatio: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(parsing: argument)
    }

    public static var allValueStrings: [String] { Self.allCases.map(\.rawValue) }
}

extension ImageResolution: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(parsing: argument)
    }

    public static var allValueStrings: [String] { Self.allCases.map(\.rawValue) }
}
