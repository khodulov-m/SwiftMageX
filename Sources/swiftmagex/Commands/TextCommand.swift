import ArgumentParser
import Foundation
import SwiftMageXKit

/// `swiftmagex text <input> --text "<string>" [options]` — text overlay.
///
/// Per spec §6.3. Stubbed until milestone 3.
struct TextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Overlay text onto an image — no AI."
    )

    @Argument(help: "Source image file.")
    var input: String

    @Option(name: .long, help: "Text to overlay onto the image.")
    var text: String

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Anchor position of the overlay.",
            valueName: "top|center|bottom|top-left|top-right|bottom-left|bottom-right"
        )
    )
    var position: TextPosition = .bottom

    @Option(name: .long, help: "Font family name. Defaults to the system font.")
    var font: String?

    @Option(name: .customLong("font-size"), help: "Glyph point size.")
    var fontSize: Int = 48

    @Option(name: .long, help: "Fill color in #RRGGBB or #RRGGBBAA form.")
    var color: String = "#FFFFFF"

    @Option(name: .long, help: "Stroke color in #RRGGBB form. Omit for no stroke.")
    var stroke: String?

    @Option(name: .customLong("stroke-width"), help: "Stroke width in points.")
    var strokeWidth: Double = 2.0

    @Option(name: [.customShort("o"), .long], help: "Destination file. Defaults to a sibling of the source.")
    var output: String?

    @OptionGroup var globals: GlobalOptions

    func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("--text must not be empty.")
        }
        guard fontSize > 0 else {
            throw ValidationError("--font-size must be positive (got \(fontSize)).")
        }
        guard strokeWidth >= 0 else {
            throw ValidationError("--stroke-width must be non-negative (got \(strokeWidth)).")
        }
    }

    func run() async throws {
        // TODO(milestone 3): load via CoreImageRasterEngine, build a TextSpec,
        // overlay, write to the resolved output path, and emit a result via
        // ResultPrinter (human or JSON).
        FileHandle.standardError.write(Data(
            "swiftmagex text is not implemented yet (milestone 3).\n".utf8
        ))
        throw ExitCode(1)
    }
}

extension TextPosition: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    public static var allValueStrings: [String] { Self.allCases.map(\.rawValue) }
}
