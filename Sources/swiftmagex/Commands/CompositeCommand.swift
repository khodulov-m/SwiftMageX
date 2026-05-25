import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex composite <background> --overlay <fg> [options]` — alpha compositing.
///
/// Local raster compositing — no AI, no API key. Pastes one image onto another
/// at an anchored, scaled position.
struct CompositeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "composite",
        abstract: "Composite one image onto another — no AI."
    )

    @Argument(help: "Background image file (the canvas).")
    var input: String

    @Option(name: .long, help: "Foreground image pasted onto the background.")
    var overlay: String

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Anchor position of the foreground.",
            valueName: "top|center|bottom|top-left|top-right|bottom-left|bottom-right"
        )
    )
    var position: TextPosition = .center

    @Option(name: .long, help: "Foreground size as a fraction of the background (0–1+).")
    var scale: Double = 1.0

    @Option(name: .customLong("offset-x"), help: "Horizontal nudge in pixels (positive = right).")
    var offsetX: Int = 0

    @Option(name: .customLong("offset-y"), help: "Vertical nudge in pixels (positive = down).")
    var offsetY: Int = 0

    @Option(name: .long, help: "Foreground opacity, 0.0–1.0.")
    var opacity: Double = 1.0

    @Option(name: [.customShort("o"), .long], help: "Destination file. Defaults to a sibling of the background.")
    var output: String?

    @Option(
        name: .long,
        help: ArgumentHelp("Output format. Defaults to the background format.", valueName: "png|jpeg")
    )
    var format: ImageFormat?

    @Option(name: .long, help: "JPEG quality, 0.0–1.0.")
    var quality: Double = 0.9

    @OptionGroup var globals: GlobalOptions

    func validate() throws {
        guard scale > 0 else {
            throw ValidationError("--scale must be positive (got \(scale)).")
        }
        guard (0.0...1.0).contains(opacity) else {
            throw ValidationError("--opacity must be between 0.0 and 1.0 (got \(opacity)).")
        }
        guard (0.0...1.0).contains(quality) else {
            throw ValidationError("--quality must be between 0.0 and 1.0 (got \(quality)).")
        }
    }

    func run() async throws {
        let printer = ResultPrinter(json: globals.json, verbose: globals.verbose)
        let spec = CompositeSpec(
            position: position,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY,
            opacity: opacity
        )

        do {
            let written = try SwiftMageXOrchestrator.composite(
                input: input,
                overlay: overlay,
                spec: spec,
                output: output,
                format: format,
                quality: quality
            )
            printer.printSuccess(
                command: "composite",
                outputs: [JSONResultEnvelope.Output(
                    path: written.path.path,
                    format: written.format,
                    width: written.width,
                    height: written.height
                )]
            )
        } catch let error as SwiftMageXError {
            printer.printError(error, command: "composite")
            throw ExitCode(error.exitCode)
        }
    }
}
