import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex crop <input> --aspect W:H [options]` — saliency-aware crop.
///
/// Uses Vision's on-device attention saliency to pick the crop offset, so the
/// salient subject lands inside the requested aspect-ratio window instead of
/// the geometric center. No AI provider, no API key, zero quota.
struct CropCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "crop",
        abstract: "Smart-crop an image to an aspect ratio using Vision saliency — no AI, no key."
    )

    @Argument(help: "Source image file.")
    var input: String

    @Option(
        name: .long,
        help: ArgumentHelp("Target aspect ratio, e.g. 1:1, 4:5, 9:16.", valueName: "W:H")
    )
    var aspect: String

    @Option(name: [.customShort("o"), .long], help: "Destination file. Defaults to a sibling of the source.")
    var output: String?

    @Option(
        name: .long,
        help: ArgumentHelp("Output format. Defaults to the source format.", valueName: "png|jpeg")
    )
    var format: ImageFormat?

    @Option(name: .long, help: "JPEG quality, 0.0–1.0.")
    var quality: Double = 0.9

    @OptionGroup var globals: GlobalOptions

    func validate() throws {
        _ = try Self.parseAspect(aspect)
        guard (0.0...1.0).contains(quality) else {
            throw ValidationError("--quality must be between 0.0 and 1.0 (got \(quality)).")
        }
    }

    func run() async throws {
        let printer = ResultPrinter(json: globals.json, verbose: globals.verbose)

        // Diagnostic: surface the resolved output format for `--verbose`.
        // The orchestrator handles the same detection internally; re-derive
        // it only to print a friendly hint here.
        if format == nil {
            let inputURL = URL(
                fileURLWithPath: input,
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            ).standardizedFileURL
            if let detected = ImageFormat.detect(at: inputURL) {
                printer.diagnostic("detected source format: \(detected.rawValue)")
            } else {
                printer.diagnostic("source format not writable; defaulting output to png")
            }
        }

        do {
            let parsed = try Self.parseAspect(aspect)
            let spec = SmartCropSpec(aspectWidth: parsed.width, aspectHeight: parsed.height)
            let written = try SwiftMageXOrchestrator.smartCrop(
                input: input,
                spec: spec,
                output: output,
                format: format,
                quality: quality
            )
            printer.printSuccess(
                command: "crop",
                outputs: [JSONResultEnvelope.Output(
                    path: written.path.path,
                    format: written.format,
                    width: written.width,
                    height: written.height
                )]
            )
        } catch let error as SwiftMageXError {
            printer.printError(error, command: "crop")
            throw ExitCode(error.exitCode)
        }
    }

    /// Parses a `W:H` aspect string into two positive ints. Throws a
    /// `ValidationError` so ArgumentParser surfaces it as a usage problem
    /// (exit code 2) before `run()` is even called.
    static func parseAspect(_ raw: String) throws -> (width: Int, height: Int) {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let w = Int(parts[0]), let h = Int(parts[1]),
              w > 0, h > 0 else {
            throw ValidationError("--aspect must be of the form W:H with positive integers (got \"\(raw)\").")
        }
        return (w, h)
    }
}
